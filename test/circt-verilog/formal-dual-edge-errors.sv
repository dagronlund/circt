// RUN: split-file %s %t
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/clocks.sv 2>&1 | FileCheck %s
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/checks.sv 2>&1 | FileCheck %s
// REQUIRES: slang
// CHECK: error: unsupported formal process

//--- clocks.sv
module top(input logic a, b, output logic q);
  initial q = 1'b1;
  always @(posedge a or negedge b) q <= ~q;
endmodule

//--- checks.sv
module top(input logic clk, output logic q);
  initial q = 1'b1;
  always @(posedge clk or negedge clk) begin
    q <= ~q;
    assert (q);
  end
endmodule
