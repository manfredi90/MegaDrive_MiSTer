// Behavioural model of the VRAM block: registered address, read shows the new data.
module vram_ip
(
	input	  [7:0] address,
	input	 [31:0] byteena,
	input	        clock,
	input	[255:0] data,
	input	        wren,
	output[255:0] q
);
	reg [255:0] m[0:255];
	reg   [7:0] a;
	integer i;
	always @(posedge clock) begin
		if(wren) for(i = 0; i < 32; i = i + 1) if(byteena[i]) m[address][i*8 +: 8] <= data[i*8 +: 8];
		a <= address;
	end
	assign q = m[a];
endmodule
