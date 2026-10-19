// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=verif.assume
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=verif.assume
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=verif.assume
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=verif.assume
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=verif.assume
// REQUIRES: slang

// Unroll the startup loop, forwarding each blocking assignment to the next
// iteration. Four iterations happen to restore the declaration value.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %enable : i1
// CHECK-DAG: [[Q:%.+]] = seq.firreg [[NEXT:%.+]] clock {{%.+}} preset 1{{.*}} : i8
// CHECK-DAG: [[NEXT]] = comb.mux bin %enable, {{%.+}}, [[Q]] : i8
// CHECK: hw.output [[Q]] : i8
module top(input logic clk, enable, output logic [7:0] q);
  bit [7:0] seed = 8'h01;
  initial begin
    for (logic [2:0] i = 0; i < 4; i++)
      seed = {seed[2:0], seed[7:3]} ^ 8'h74;
  end
  always @(posedge clk)
    if (enable) seed <= {seed[6:0], seed[7] ^ seed[5]};
  always_comb q = seed;
endmodule

// Three iterations produce 0xAB. This catches both dropping the loop entirely
// and repeatedly reading the declaration value instead of the preceding write.
// CHECK-LABEL: hw.module @three_iterations(in %clk : i1, in %enable : i1
// CHECK-DAG: [[Q:%.+]] = seq.firreg [[NEXT:%.+]] clock {{%.+}} preset 171{{.*}} : i8
// CHECK-DAG: [[NEXT]] = comb.mux bin %enable, {{%.+}}, [[Q]] : i8
// CHECK: hw.output [[Q]] : i8
module three_iterations(input logic clk, enable, output logic [7:0] q);
  bit [7:0] seed = 8'h01;
  initial begin
    for (logic [2:0] i = 0; i < 3; i++)
      seed = {seed[2:0], seed[7:3]} ^ 8'h74;
  end
  always @(posedge clk)
    if (enable) seed <= {seed[6:0], seed[7] ^ seed[5]};
  always_comb q = seed;
endmodule
