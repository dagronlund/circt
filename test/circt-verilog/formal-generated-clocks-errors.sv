// RUN: not circt-verilog --lower-llhd-formal-to-core %s 2>&1 | FileCheck %s
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: not circt-opt %t.hw.mlir --lower-llhd-formal-to-core 2>&1 | FileCheck %s
// REQUIRES: slang

// Recovering partial output drives must not hide two clocks writing the same
// element. The untouched element is only probe padding, but q[0] truly overlaps.
// CHECK: error: signal must have exactly one resolved driver
module top(input logic [1:0] clk, input logic [1:0] d,
           output logic q [2]);
  always @(edge clk[0]) q[0] <= d[0];
  always @(edge clk[1]) q[0] <= d[1];
  always_comb q[1] = 1'b0;
endmodule
