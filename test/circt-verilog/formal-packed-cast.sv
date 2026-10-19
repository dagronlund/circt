// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// CHECK-LABEL: hw.module private @small_reg(in %clk : i1, in %d : i3
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[STATE:%.+]] = seq.firreg %d clock [[CLK]] : i3
// CHECK-NEXT: hw.output [[STATE]] : i3
module small_reg(input logic clk, input logic [2:0] d, output logic [2:0] q);
  always_ff @(posedge clk) q <= d;
endmodule

// The upper five bits are undriven, but the packed cast truncates them away.
// They must be discarded before formal validation, without filling live bits
// from scheduling initializers or introducing a preset on the child register.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %mask : i3
// CHECK: [[STATE:%.+]] = hw.instance "u_reg" @small_reg
// CHECK: hw.output [[STATE]] : i3
module top(input logic clk, input logic [2:0] mask, output logic [2:0] q);
  logic [0:0][7:0] words;
  logic [0:0][7:0] next_words;
  logic [2:0] value;
  always_comb begin
    value = 3'(words);
    next_words = value | mask;
    q = value;
  end
  small_reg u_reg(.clk(clk), .d(3'(next_words[0])), .q(words[0][2:0]));
endmodule
