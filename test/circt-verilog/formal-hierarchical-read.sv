// RUN: circt-verilog --top top --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --top top --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --top top --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --top top --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --top nested_top --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --check-prefix=NESTED --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --top nested_top --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --check-prefix=NESTED --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// Observing a child's internal register must export its sampled value and
// retain the child's ownership of the register, without inventing a preset.
// CHECK-LABEL: hw.module private @child(in %clk : i1, in %d : i1, out q : i1)
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[Q:%.+]] = seq.firreg %d clock [[CLK]] {{.*}}: i1
// CHECK-NEXT: hw.output [[Q]] : i1
module child(input logic clk, d);
  logic q;
  always_ff @(posedge clk) q <= d;
endmodule

// CHECK-LABEL: hw.module @top(in %clk : i1, in %d : i1, out y : i1)
// CHECK: [[Q:%.+]] = hw.instance "u_child" @child(clk: %clk: i1, d: %d: i1) -> (q: i1)
// CHECK-NEXT: hw.output [[Q]] : i1
module top(input logic clk, d, output logic y);
  child u_child(.clk(clk), .d(d));
  always_comb y = u_child.q;
endmodule

module wrapper(input logic clk, d);
  child u_child(.clk(clk), .d(d));
endmodule

// The same reference can be forwarded through intermediate modules. Sibling
// instances must retain independent state and distinct data connections.
// NESTED: seq.firreg %d clock
// NESTED-LABEL: hw.module @nested_top
// NESTED: hw.instance "left"
// NESTED: hw.instance "right"
// NESTED: hw.output
module nested_top(input logic clk, input logic [1:0] d, output logic [1:0] y);
  wrapper left(.clk(clk), .d(d[0]));
  wrapper right(.clk(clk), .d(d[1]));
  always_comb y = {right.u_child.q, left.u_child.q};
endmodule
