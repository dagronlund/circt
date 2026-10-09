// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// Independent array elements have independent drivers.
// CHECK-LABEL: hw.module @comb_array(in %a : i1, in %b : i1
// CHECK-NOT: seq.
// CHECK: [[Y:%.+]] = comb.or %a, %b : i1
// CHECK-NEXT: hw.output [[Y]] : i1
module comb_array(input logic a, b, output logic y);
  logic values [2];
  always_comb values[0] = a;
  always_comb values[1] = b;
  always_comb y = values[0] | values[1];
endmodule

// Only the clocked element becomes a register, with no invented initial value.
// CHECK-LABEL: hw.module @mixed_array(in %clk : i1, in %din : i1
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[Q:%.+]] = seq.firreg %din clock [[CLK]] : i1
// CHECK-NEXT: hw.output [[Q]] : i1
module mixed_array(input logic clk, din, output logic dout);
  logic pipe[0:1];
  always_comb pipe[0] = din;
  always_ff @(posedge clk) pipe[1] <= pipe[0];
  always_comb dout = pipe[1];
endmodule

// Descending indices must preserve which element is combinational and clocked.
// CHECK-LABEL: hw.module @descending_array(in %clk : i1, in %din : i3
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[Q:%.+]] = seq.firreg %din clock [[CLK]] : i3
// CHECK-NEXT: hw.output [[Q]] : i3
module descending_array(input logic clk, input logic [2:0] din,
                        output logic [2:0] dout);
  logic [2:0] pipe[1:0];
  always_comb pipe[0] = din;
  always_ff @(posedge clk) pipe[1] <= pipe[0];
  always_comb dout = pipe[1];
endmodule

// Splitting nested aggregates must preserve unconstrained state recursively.
// CHECK-LABEL: hw.module @nested_array(in %clk : i1, in %din : i1
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[Q:%.+]] = seq.firreg %din clock [[CLK]] : i1
// CHECK-NEXT: hw.output [[Q]] : i1
module nested_array(input logic clk, din, output logic dout);
  logic pipe[0:0][0:1];
  always_comb pipe[0][0] = din;
  always_ff @(posedge clk) pipe[0][1] <= pipe[0][0];
  always_comb dout = pipe[0][1];
endmodule

// An instance output and a procedural assignment drive disjoint packed slices
// of an array element. Split both the array and its integer element.
// CHECK-LABEL: hw.module private @packed_nibble(in %clk : i1, in %d : i4
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[Q:%.+]] = seq.firreg %d clock [[CLK]] : i4
// CHECK-NEXT: hw.output [[Q]] : i4
module packed_nibble(input logic clk, input logic [3:0] d,
                     output logic [3:0] q);
  always_ff @(posedge clk) q <= d;
endmodule

// CHECK-LABEL: hw.module @packed_slice_instance(in %clk : i1, in %d : i4
// CHECK-DAG: [[ZERO:%.+]] = hw.constant 0 : i4
// CHECK-DAG: [[Q:%.+]] = hw.instance "inst" @packed_nibble(clk: %clk: i1, d: %d: i4) -> (q: i4)
// CHECK-DAG: [[WORD:%.+]] = comb.concat [[ZERO]], [[Q]] : i4, i4
// CHECK: hw.output [[WORD]] : i8
module packed_slice_instance(input logic clk, input logic [3:0] d,
                             output logic [7:0] q);
  logic [0:0][7:0] words;
  packed_nibble inst(.clk, .d, .q(words[0][3:0]));
  always_comb words[0][7:4] = '0;
  always_comb q = words[0];
endmodule
