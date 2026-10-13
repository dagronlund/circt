// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// REQUIRES: slang

// Declaration initialization precedes the blocking startup update. The final
// constant startup value becomes the enabled register's preset in every flow.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %enable : i1
// CHECK-DAG: [[Q:%.+]] = seq.firreg [[NEXT:%.+]] clock {{%.+}} preset 91{{.*}} : i8
// CHECK-DAG: [[NEXT]] = comb.mux bin %enable, {{%.+}}, [[Q]] : i8
// CHECK: hw.output [[Q]] : i8
module top(input logic clk, enable, output logic [7:0] q);
  bit [7:0] seed = 8'h01;
  initial seed = seed ^ 8'h5A;
  always @(posedge clk) if (enable) seed <= {seed[6:0], seed[7] ^ seed[5]};
  always_comb q = seed;
endmodule
