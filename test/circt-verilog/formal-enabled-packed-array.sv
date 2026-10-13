// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// Ordinary register extraction hides both partial array writes behind
// whole-array registers. Recover two independent, uninitialized four-bit
// registers and retain each lane's enable feedback and synchronous reset.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %rst : i1, in %enable : i2, in %d : !hw.array<2xi4>
// CHECK-DAG: [[Q0:%.+]] = seq.firreg [[NEXT0:%.+]] clock {{%.+}}{{.*}} : i4
// CHECK-DAG: [[NEXT0]] = comb.mux bin {{.*}}[[Q0]]{{.*}} : i4
// CHECK-DAG: [[Q1:%.+]] = seq.firreg [[NEXT1:%.+]] clock {{%.+}}{{.*}} : i4
// CHECK-DAG: [[NEXT1]] = comb.mux bin {{.*}}[[Q1]]{{.*}} : i4
// CHECK: [[Q:%.+]] = hw.array_create [[Q1]], [[Q0]] : i4
// CHECK-NEXT: hw.output [[Q]] : !hw.array<2xi4>
module top(input logic clk, rst, input logic [1:0] enable,
           input logic [1:0][3:0] d, output logic [1:0][3:0] q);
  logic [1:0][3:0] pipe;
  for (genvar i = 0; i < 2; i++) begin: gen_pipe
    always_ff @(posedge clk) begin
      if (rst)
        pipe[i] <= '0;
      else if (enable[i])
        pipe[i] <= d[i];
    end
  end
  always_comb q = pipe;
endmodule
