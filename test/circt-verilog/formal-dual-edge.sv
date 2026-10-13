// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: FileCheck %s --check-prefix=HW < %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// REQUIRES: slang

// Ordinary extraction retains the constant startup drive's provenance and
// leaves dual-edge state in LLHD. Formal lowering encodes its two phases.
// HW-LABEL: hw.module @top
// HW: llhd.drv {{.*}} {llhd.initial} : i1
// HW: llhd.process
// CHECK-LABEL: hw.module @top
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[NEG:%.+]] = seq.clock_inv [[CLK]]
// CHECK: [[RISE:%.+]] = seq.firreg {{%.+}} clock [[CLK]] preset 1{{.*}} : i1
// CHECK: [[FALL:%.+]] = seq.firreg {{%.+}} clock [[NEG]] preset 0{{.*}} : i1
// CHECK: [[Q:%.+]] = comb.xor {{(bin )?}}[[RISE]], [[FALL]] : i1
// CHECK: hw.output [[Q]] : i1
module top(input logic clk, output logic clk_div);
  initial clk_div = 1'b1;
  always @(posedge clk or negedge clk) clk_div <= ~clk_div;
endmodule

// The same encoding must handle arbitrary data and conditional updates.
// CHECK-LABEL: hw.module @enabled
// CHECK: seq.clock_inv
// CHECK: seq.firreg {{.*}} preset 5{{.*}} : i3
// CHECK: seq.firreg {{.*}} preset 0{{.*}} : i3
// CHECK: hw.output {{%.+}} : i3
module enabled(input logic clk, enable, input logic [2:0] d, output logic [2:0] q);
  logic [2:0] state = 3'b101;
  always @(posedge clk or negedge clk) if (enable) state <= d;
  always_comb q = state;
endmodule

// The auxiliary zero preset must not constrain observable uninitialized state.
// CHECK-LABEL: hw.module @uninitialized
// CHECK: seq.firreg {{.*}} clock {{%[^ ]+}}{{( \{name = "[^"]+"\})?}} : i1
// CHECK: seq.firreg {{.*}} preset 0{{.*}} : i1
// CHECK: hw.output {{%.+}} : i1
module uninitialized(input logic clk, d, output logic q);
  always @(posedge clk or negedge clk) q <= d;
endmodule
