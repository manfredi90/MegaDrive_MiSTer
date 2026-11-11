// Simulation model of the Quartus dffeas primitive, as used by the scan netlist
// (asynchronous inputs tied off): the clock enable gates the synchronous load and clear.
module dffeas (output reg q, input d, clk, clrn, prn, ena, asdata, aload, sclr, sload);
	parameter power_up = "DONT_CARE";
	parameter is_wysiwyg = "false";
	initial q = power_up == "high";
	always @(posedge clk) if (ena) q <= sclr ? 1'b0 : sload ? asdata : d;
endmodule
