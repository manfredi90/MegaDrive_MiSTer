// Savestate test driver.
//   sim frames <n> <out.ppm>   run n frames, write the last one as an image, print RAM counters
//   sim trace <cycles> <file>  write the per-cycle output hash (to compare RTL and netlist)
//   sim test <seed>            save/restore checks against an uninterrupted reference run
#include "Vtb.h"
#include "Vtb___024root.h"
#include "Vtb_tb.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <fstream>
#include <memory>
#include <random>
#include <string>
#include <vector>

// Leave without running destructors: tearing down two models linked with the protected
// netlist library deadlocks in the Verilator runtime.
[[noreturn]] static void quit(int rc)
{
	fflush(stdout);
	_exit(rc);
}

static int chain_len()
{
	std::ifstream f("md_core_ss.vh");
	std::string s((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
	size_t p = s.find("SS_CHAIN_LEN = ");
	return p == std::string::npos ? 0 : atoi(s.c_str() + p + 15);
}

struct Mem { int sel, size, bits; };
// (the work RAM index has address bit 13 inverted: IA14 = ~VA13 on this board)
// order and sizes of the memories reachable through ss_mem_*
static const Mem MEMS[] = {
	{0, 40, 11}, {1, 80, 21}, {2, 20, 34}, {3, 40, 56}, {4, 64, 9},
	{5, 65536, 8}, {6, 32768, 16}, {7, 8192, 8},
};

struct Snapshot {
	std::vector<uint8_t> chain;
	std::vector<std::vector<uint64_t>> mem;
	uint64_t t = 0;
};

struct Sim {
	std::unique_ptr<VerilatedContext> ctx;
	std::unique_ptr<Vtb> top;
	uint64_t t = 0;      // emulated (normal) cycles since reset release
	uint64_t ticks = 0;

	Sim()
	{
		ctx.reset(new VerilatedContext);
		top.reset(new Vtb(ctx.get()));
		top->reset = 1;
		for (int i = 0; i < 2000; i++) tick();
		top->reset = 0;
	}

	void tick()
	{
		top->clk = 0; top->eval();
		top->clk = 1; top->eval();
		ticks++;
	}

	uint32_t sig() const
	{
		uint64_t v = top->V_R | top->V_G << 8 | top->V_B << 16 | (uint64_t)top->V_HS << 24 | (uint64_t)top->V_VS << 25
			| (uint64_t)top->vdp_de_h << 26 | (uint64_t)top->vdp_de_v << 27 | (uint64_t)top->cart_busy << 28
			| (uint64_t)top->MOL << 29 | (uint64_t)top->MOR << 38 | (uint64_t)top->PSG << 47;
		v ^= v >> 33; v *= 0xff51afd7ed558ccdULL; v ^= v >> 33;
		return (uint32_t)v;
	}

	uint32_t step() { tick(); t++; return sig(); }

	void hold(bool on) { top->ss_hold = on; }

	// Rotate the scan chain once around, reading it out (the state is unchanged afterwards).
	void scan_read(std::vector<uint8_t> &bits, int len)
	{
		bits.resize(len);
		top->ss_shift = 1;
		for (int i = 0; i < len; i++) {
			top->eval();
			bits[i] = top->ss_out;
			top->ss_in = top->ss_out;
			tick();
		}
		top->ss_shift = 0;
	}

	void scan_write(const std::vector<uint8_t> &bits)
	{
		top->ss_shift = 1;
		for (uint8_t b : bits) { top->ss_in = b; tick(); }
		top->ss_shift = 0;
	}

	void mem_read(const Mem &m, std::vector<uint64_t> &data)
	{
		data.resize(m.size);
		top->ss_mem_act = 1;
		top->ss_mem_sel = m.sel;
		top->ss_mem_we = 0;
		// the address is taken at one clock edge, the data is out after the next one
		for (int a = 0; a <= m.size; a++) {
			top->ss_mem_addr = a < m.size ? a : 0;
			tick();
			if (a >= 1) data[a - 1] = top->ss_mem_rdata & ((1ULL << m.bits) - 1);
		}
		top->ss_mem_act = 0;
	}

	void mem_write(const Mem &m, const std::vector<uint64_t> &data)
	{
		top->ss_mem_act = 1;
		top->ss_mem_sel = m.sel;
		top->ss_mem_we = 1;
		for (int a = 0; a < m.size; a++) {
			top->ss_mem_addr = a;
			top->ss_mem_wdata = data[a];
			tick();
		}
		top->ss_mem_we = 0;
		top->ss_mem_act = 0;
	}

	void refresh()
	{
		top->ss_refresh = 1;
		tick();
		top->ss_refresh = 0;
	}

	void wait_idle(std::vector<uint32_t> *ref)
	{
		while (top->cart_busy) check(ref);
	}

	bool check(std::vector<uint32_t> *ref)
	{
		uint32_t s = step();
		if (ref && t - 1 < ref->size() && (*ref)[t - 1] != s) {
			printf("MISMATCH at cycle %llu\n", (unsigned long long)(t - 1));
			quit(1);
		}
		return true;
	}

	void save(Snapshot &s, int len)
	{
		hold(true);
		scan_read(s.chain, len);
		s.mem.resize(sizeof(MEMS) / sizeof(MEMS[0]));
		for (size_t i = 0; i < s.mem.size(); i++) mem_read(MEMS[i], s.mem[i]);
		refresh();
		hold(false);
		s.t = t;
	}

	void load(const Snapshot &s)
	{
		hold(true);
		scan_write(s.chain);
		for (size_t i = 0; i < s.mem.size(); i++) mem_write(MEMS[i], s.mem[i]);
		refresh();
		hold(false);
		t = s.t;
	}

	void scramble(std::mt19937_64 &rng, int len)
	{
		hold(true);
		std::vector<uint8_t> bits(len);
		for (auto &b : bits) b = rng() & 1;
		scan_write(bits);
		for (const Mem &m : MEMS) {
			std::vector<uint64_t> d(m.size);
			for (auto &v : d) v = rng() & ((1ULL << m.bits) - 1);
			mem_write(m, d);
		}
		hold(false);
	}

	uint16_t ram68(int word) const { return top->rootp->tb->ram_68k[word]; }

	// controller mode: a tick only advances the core when ss_hold is low at that edge
	std::mt19937_64 *busy_rng = nullptr;
	bool ctrl_step(std::vector<uint32_t> *ref)
	{
		bool held = top->ctrl_hold;
		if (busy_rng) top->ddr_busy_rnd = ((*busy_rng)() & 3) == 0;
		tick();
		if (held) return false;
		t++;
		uint32_t s = sig();
		if (ref && t - 1 < ref->size() && (*ref)[t - 1] != s) {
			printf("MISMATCH at cycle %llu\n", (unsigned long long)(t - 1));
			quit(1);
		}
		return true;
	}

	uint64_t ctrl_op(bool save, int slot, std::vector<uint32_t> *ref)
	{
		top->ctrl_slot = slot;
		(save ? top->ctrl_save : top->ctrl_load) = 1;
		ctrl_step(ref);
		top->ctrl_save = top->ctrl_load = 0;
		uint64_t frozen_at = 0, n = 0;
		while (top->ctrl_busy || top->ctrl_hold) {
			if (top->ctrl_hold && !frozen_at) frozen_at = t;
			ctrl_step(ref);
			n++;
		}
		printf("  %s took %llu clocks\n", save ? "save" : "load", (unsigned long long)n);
		return frozen_at;
	}

	void fill_cart(std::mt19937_64 &rng)
	{
		// the save port reaches the first 32K words (64 KB) of the backup RAM
		for (int i = 0; i < 32768; i++) top->rootp->tb->sram[i] = rng();
		for (int i = 0; i < 3; i++) top->rootp->tb->cart_regs[i] = rng();
	}

	bool cart_equal(const Sim &o) const
	{
		for (int i = 0; i < 32768; i++) if (top->rootp->tb->sram[i] != o.top->rootp->tb->sram[i]) return false;
		for (int i = 0; i < 3; i++) if (top->rootp->tb->cart_regs[i] != o.top->rootp->tb->cart_regs[i]) return false;
		return true;
	}
};

static const uint64_t FRAME = 1792000;

static void frames(int n, const char *out)
{
	Sim s;
	std::vector<uint8_t> img;
	int x = 0, y = 0, w = 0, h = 0;
	bool old_hclk = 0, old_de = 0, old_vs = 0;
	int frame = 0;
	while (frame < n) {
		s.step();
		Vtb *tp = s.top.get();
		if (getenv("DUMPRAM") && s.t % 200000 == 0) printf("  t=%llu addr=%06x\n", (unsigned long long)s.t, tp->dbg_m68k_addr * 2);
		if (tp->V_VS && !old_vs) {
			frame++;
			if (frame < n) { img.clear(); w = h = 0; y = 0; }
		}
		old_vs = tp->V_VS;
		bool de = tp->vdp_de_h && tp->vdp_de_v;
		if (tp->vdp_hclk1 && !old_hclk && de) {
			img.push_back(tp->V_R); img.push_back(tp->V_G); img.push_back(tp->V_B);
			x++;
		}
		if (old_de && !de) { if (x > w) w = x; if (x) { y++; h = y; } x = 0; }
		old_hclk = tp->vdp_hclk1; old_de = de;
	}
	printf("frames=%d cycles=%llu  vint=%u hint=%u z80cnt=%u  image %dx%d\n", n, (unsigned long long)s.t,
		s.ram68(0x5800), s.ram68(0x5801), s.ram68(0x6002) >> 8, w, h);
	if (getenv("DUMPRAM")) {
		int nz = 0;
		for (int i = 0; i < 32768; i++) if (s.ram68(i)) { if (nz < 12) printf("  ram[%04x]=%04x\n", i * 2, s.ram68(i)); nz++; }
		printf("  nonzero words: %d\n", nz);
	}
	if (w && h && out) {
		FILE *f = fopen(out, "wb");
		fprintf(f, "P6 %d %d 255\n", w, h);
		fwrite(img.data(), 1, (size_t)w * h * 3, f);
		fclose(f);
	}
}

static void dump(uint64_t from, uint64_t to)
{
	Sim s;
	while (s.t < from) s.step();
	while (s.t < to) {
		s.step();
		Vtb *p = s.top.get();
		printf("%llu rgb=%02x%02x%02x hs=%d vs=%d de=%d%d cart=%02x mol=%03x mor=%03x psg=%04x a=%06x\n",
			(unsigned long long)(s.t - 1), p->V_R, p->V_G, p->V_B, p->V_HS, p->V_VS, p->vdp_de_h, p->vdp_de_v,
			p->dbg_cart, p->MOL, p->MOR, p->PSG, p->dbg_m68k_addr * 2);
	}
}

static void trace(uint64_t cycles, const char *file)
{
	Sim s;
	FILE *f = fopen(file, "wb");
	for (uint64_t i = 0; i < cycles; i++) { uint32_t v = s.step(); fwrite(&v, 4, 1, f); }
	fclose(f);
}

static void test(unsigned seed)
{
	int len = chain_len();
	if (!len) { printf("no md_core_ss.vh\n"); quit(1); }
	std::mt19937_64 rng(seed);
	const uint64_t T = 4 * FRAME;

	printf("reference run...\n");
	std::vector<uint32_t> ref(T);
	std::vector<uint16_t> ref_ram(32768);
	{
		Sim s;
		for (uint64_t i = 0; i < T; i++) ref[i] = s.step();
		for (int i = 0; i < 32768; i++) ref_ram[i] = s.ram68(i);
	}

	Sim s;
	uint64_t k1 = FRAME + rng() % FRAME;
	uint64_t k2 = k1 + FRAME / 4 + rng() % FRAME;
	while (s.t < k1) s.check(&ref);
	s.wait_idle(&ref);
	Snapshot snap;
	s.save(snap, len);
	printf("saved at cycle %llu (chain %d bits)\n", (unsigned long long)snap.t, len);
	while (s.t < k2) s.check(&ref);
	printf("  running on after the save matches the reference\n");
	s.wait_idle(&ref);
	uint64_t at = s.t;
	s.scramble(rng, len);
	s.load(snap);
	printf("loaded at cycle %llu\n", (unsigned long long)at);
	while (s.t < T) s.check(&ref);
	for (int i = 0; i < 32768; i++)
		if (s.ram68(i) != ref_ram[i]) { printf("RAM MISMATCH at word %d\n", i); quit(1); }
	printf("  replay after the load matches the reference up to cycle %llu, work RAM identical\n",
		(unsigned long long)T);
	printf("PASS\n");
	quit(0);   // before the Sim destructors run
}

// Save and load through ss_ctrl/ss_ddr with a DDR model that stalls at random.
static void test_ctrl(unsigned seed)
{
	std::mt19937_64 rng(seed), busy(seed * 7 + 1);
	const uint64_t T = 4 * FRAME;

	printf("reference run...\n");
	std::vector<uint32_t> ref(T);
	Sim r;
	r.top->use_ctrl = 1;
	{ std::mt19937_64 c(seed + 100); r.fill_cart(c); }
	while (r.t < T) r.ctrl_step(nullptr), ref[r.t - 1] = r.sig();

	Sim s;
	s.top->use_ctrl = 1;
	s.busy_rng = &busy;
	{ std::mt19937_64 c(seed + 100); s.fill_cart(c); }
	uint64_t k1 = FRAME + rng() % FRAME;
	uint64_t k2 = k1 + FRAME / 4 + rng() % FRAME;
	while (s.t < k1) s.ctrl_step(&ref);
	uint64_t saved = s.ctrl_op(true, 1, &ref);
	printf("saved at cycle %llu\n", (unsigned long long)saved);
	while (s.t < k2) s.ctrl_step(&ref);
	printf("  running on after the save matches the reference\n");

	// spoil the cartridge state and VRAM so the load has something to fix
	s.fill_cart(rng);
	s.top->use_ctrl = 0;
	s.hold(true);
	{ std::vector<uint64_t> d(65536); for (auto &v : d) v = rng() & 0xFF; s.mem_write(MEMS[5], d); }
	s.refresh();
	s.hold(false);
	s.top->use_ctrl = 1;
	printf("loading at cycle %llu\n", (unsigned long long)s.t);
	s.ctrl_op(false, 1, nullptr);
	s.t = saved;
	while (s.t < T) s.ctrl_step(&ref);
	for (int i = 0; i < 32768; i++)
		if (s.ram68(i) != r.ram68(i)) { printf("RAM MISMATCH at word %d\n", i); quit(1); }
	if (!s.cart_equal(r)) { printf("CART STATE MISMATCH\n"); quit(1); }
	printf("  replay after the load matches the reference, work RAM and cartridge state identical\n");

	// a load from an empty slot must be ignored
	s.ctrl_op(false, 3, &ref);
	printf("PASS\n");
	quit(0);   // before the Sim destructors run
}

int main(int argc, char **argv)
{
	setvbuf(stdout, nullptr, _IOLBF, 0);
	Verilated::commandArgs(argc, argv);
	if (argc >= 2 && !strcmp(argv[1], "frames")) frames(argc > 2 ? atoi(argv[2]) : 2, argc > 3 ? argv[3] : nullptr);
	else if (argc >= 4 && !strcmp(argv[1], "dump")) dump(strtoull(argv[2], 0, 0), strtoull(argv[3], 0, 0));
	else if (argc >= 4 && !strcmp(argv[1], "trace")) trace(strtoull(argv[2], 0, 0), argv[3]);
	else if (argc >= 2 && !strcmp(argv[1], "test")) test(argc > 2 ? atoi(argv[2]) : 1);
	else if (argc >= 2 && !strcmp(argv[1], "ctrl")) test_ctrl(argc > 2 ? atoi(argv[2]) : 1);
	else { printf("usage: sim frames <n> [out.ppm] | trace <cycles> <file> | test [seed] | ctrl [seed]\n"); quit(1); }
	quit(0);
}
