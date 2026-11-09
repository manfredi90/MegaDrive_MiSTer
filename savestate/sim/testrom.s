| Savestate test ROM: keeps the 68000, VDP (planes, sprites, scroll, DMA from ROM and fill,
| H/V interrupts), Z80, YM2612 and PSG all busy so that a bad save/restore shows up as a
| difference in the video/audio trace.

	.equ	VDP_DATA, 0xC00000
	.equ	VDP_CTRL, 0xC00004
	.equ	Z80_RAM, 0xA00000
	.equ	Z80_BUSREQ, 0xA11100
	.equ	Z80_RESET, 0xA11200

	.text
	.org	0
	.long	0x00FFFE00, start
	.rept	22
	.long	unhandled
	.endr
	.long	unhandled		| spurious
	.long	unhandled		| level 1
	.long	unhandled		| level 2
	.long	unhandled		| level 3
	.long	hint			| level 4
	.long	unhandled		| level 5
	.long	vint			| level 6
	.long	unhandled		| level 7
	.rept	32
	.long	unhandled
	.endr

	.org	0x100
	.ascii	"SEGA MEGA DRIVE "

	.org	0x200
start:
	move.w	#0x2700, %sr
	lea	VDP_CTRL, %a4
	lea	VDP_DATA, %a5

	| VDP registers
	lea	vdpregs(%pc), %a0
	moveq	#(vdpregs_end-vdpregs)/2-1, %d0
1:	move.w	(%a0)+, (%a4)
	dbra	%d0, 1b

	| palette: 64 colours
	move.l	#0xC0000000, (%a4)
	moveq	#63, %d0
	moveq	#0, %d1
1:	move.w	%d1, (%a5)
	add.w	#0x0246, %d1
	and.w	#0x0EEE, %d1
	dbra	%d0, 1b

	| VSRAM
	move.l	#0x40000010, (%a4)
	moveq	#39, %d0
	moveq	#0, %d1
1:	move.w	%d1, (%a5)
	addq.w	#3, %d1
	dbra	%d0, 1b

	| tiles 0..255 from the ROM data below, via DMA (68k -> VRAM)
	move.w	#0x8134, (%a4)			| display off, DMA enable
	move.l	#tiledata, %d0
	lsr.l	#1, %d0
	move.w	#0x9300+((tiledata_end-tiledata)/2 & 0xFF), (%a4)
	move.w	#0x9400+((tiledata_end-tiledata)/2 >> 8), (%a4)
	move.w	%d0, %d1
	and.w	#0xFF, %d1
	or.w	#0x9500, %d1
	move.w	%d1, (%a4)
	lsr.l	#8, %d0
	move.w	%d0, %d1
	and.w	#0xFF, %d1
	or.w	#0x9600, %d1
	move.w	%d1, (%a4)
	lsr.l	#8, %d0
	and.w	#0x7F, %d0
	or.w	#0x9700, %d0
	move.w	%d0, (%a4)
	move.l	#0x40000080, (%a4)		| VRAM 0x0000, DMA

	| plane A (0xC000) and B (0xE000) maps: 64x32 entries each
	move.l	#0x40000003, (%a4)
	move.w	#1023, %d0
	moveq	#0, %d1
1:	move.w	%d1, (%a5)
	add.w	#0x2001+0x0800, %d1
	and.w	#0xE7FF, %d1
	dbra	%d0, 1b

	| DMA fill of the hscroll table (0xFC00)
	move.w	#0x8F01, (%a4)
	move.w	#0x93FF, (%a4)
	move.w	#0x9403, (%a4)
	move.w	#0x9780, (%a4)
	move.l	#0x7C000083, (%a4)
	move.w	#0x1234, (%a5)
1:	move.w	(%a4), %d0
	btst	#1, %d0
	bne.s	1b
	move.w	#0x8F02, (%a4)

	| Z80: take the bus, copy the program, release reset and the bus
	move.w	#0x100, Z80_BUSREQ
	move.w	#0x100, Z80_RESET
1:	btst	#0, Z80_BUSREQ
	bne.s	1b
	lea	z80prog(%pc), %a0
	lea	Z80_RAM, %a1
	move.w	#z80prog_end-z80prog-1, %d0
1:	move.b	(%a0)+, (%a1)+
	dbra	%d0, 1b
	move.w	#0, Z80_RESET
	moveq	#20, %d0
1:	dbra	%d0, 1b
	move.w	#0x100, Z80_RESET
	move.w	#0, Z80_BUSREQ

	| PSG tones
	lea	0xC00011, %a3
	move.b	#0x8F, (%a3)
	move.b	#0x10, (%a3)
	move.b	#0x92, (%a3)
	move.b	#0xAA, (%a3)
	move.b	#0x08, (%a3)
	move.b	#0xB4, (%a3)
	move.b	#0xE5, (%a3)

	lea	0xFF0000, %a6
	moveq	#0, %d7
	move.w	#0x8174, (%a4)			| display on
	move.w	#0x2000, %sr

main:
	| sprites: 80 entries in the table at 0xF000, moving with the frame counter
	move.w	frames, %d6
	move.l	#0x70000003, (%a4)
	moveq	#0, %d5
	moveq	#79, %d0
1:	move.w	%d5, %d1
	lsl.w	#2, %d1
	add.w	%d6, %d1
	and.w	#0xFF, %d1
	add.w	#128, %d1
	move.w	%d1, (%a5)			| y
	move.w	%d5, %d1
	addq.w	#1, %d1
	cmp.w	#80, %d1
	bne.s	2f
	moveq	#0, %d1
2:	move.w	%d5, %d2
	and.w	#3, %d2
	lsl.w	#8, %d2
	lsl.w	#2, %d2
	or.w	%d2, %d1
	move.w	%d1, (%a5)			| size, link
	move.w	%d5, %d1
	add.w	%d6, %d1
	or.w	#0x8000, %d1
	move.w	%d1, (%a5)			| pattern
	move.w	%d5, %d1
	mulu.w	#5, %d1
	sub.w	%d6, %d1
	and.w	#0x1FF, %d1
	move.w	%d1, (%a5)			| x
	addq.w	#1, %d5
	dbra	%d0, 1b

	| busy work in RAM: LFSR, a checksum, a divide
	move.w	#255, %d0
1:	move.l	%d7, %d1
	lsr.l	#1, %d7
	bcc.s	2f
	eor.l	#0xD0000001, %d7
2:	add.l	%d1, (%a6)
	addq.l	#4, %a6
	cmp.l	#0xFF8000, %a6
	bne.s	3f
	lea	0xFF0000, %a6
3:	dbra	%d0, 1b
	tst.l	%d7
	bne.s	1f
	moveq	#1, %d7
1:	move.l	%d7, %d1
	divu.w	#1234, %d1
	move.l	%d1, 0xFF8000

	| read the Z80 counter through the bus
	move.w	#0x100, Z80_BUSREQ
1:	btst	#0, Z80_BUSREQ
	bne.s	1b
	move.b	Z80_RAM+0x1000, 0xFF8004
	move.w	#0, Z80_BUSREQ

	| VDP data port read back
	move.l	#0x00000003, (%a4)
	move.w	(%a5), 0xFF8006

	bra	main

hint:
	addq.w	#1, hlines
	move.w	hlines, %d0
	and.w	#0x1F, %d0
	move.w	#0x8700, %d1
	or.w	%d0, %d1
	move.w	%d1, VDP_CTRL
	rte

vint:
	movem.l	%d0-%d1, -(%sp)
	addq.w	#1, frames
	move.w	frames, %d0
	| hscroll and vscroll follow the frame counter
	move.l	#0x7C000003, VDP_CTRL
	move.w	%d0, VDP_DATA
	neg.w	%d0
	move.w	%d0, VDP_DATA
	move.l	#0x40000010, VDP_CTRL
	move.w	%d0, VDP_DATA
	| toggle shadow/highlight now and then
	move.w	frames, %d0
	btst	#3, %d0
	beq.s	1f
	move.w	#0x8C89, VDP_CTRL
	bra.s	2f
1:	move.w	#0x8C81, VDP_CTRL
2:	movem.l	(%sp)+, %d0-%d1
	rte

unhandled:
	rte

	.even
vdpregs:
	.word	0x8014				| hint enable
	.word	0x8164				| display off, vint enable, md mode
	.word	0x8230				| plane A at 0xC000
	.word	0x833C				| window at 0xF000
	.word	0x8407				| plane B at 0xE000
	.word	0x8578				| sprites at 0xF000
	.word	0x8700
	.word	0x8A10				| hint every 17 lines
	.word	0x8B00
	.word	0x8C81				| H40
	.word	0x8D3F				| hscroll at 0xFC00
	.word	0x8F02
	.word	0x9001				| 64x32
	.word	0x9100
	.word	0x9200
vdpregs_end:

	.even
z80prog:
	.incbin	"z80prog.bin"
z80prog_end:

	.even
tiledata:
	.set	i, 0
	.rept	256*8
	.long	((i * 0x01234567) ^ (i << 13) ^ 0x89ABCDEF) & 0xFFFFFFFF
	.set	i, i + 1
	.endr
tiledata_end:

	.section .bss
	.org	0
frames:	.space	2
hlines:	.space	2
