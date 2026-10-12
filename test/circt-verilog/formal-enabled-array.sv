// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// REQUIRES: slang

// Only pipe_data[1] is state. Recover its update and hold mux after ordinary
// extraction has added an aggregate enable mux and copied-through element.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %rst : i1, in %enable : i1, in %d : i4
// CHECK-DAG: [[Q:%.+]] = seq.firreg [[NEXT:%.+]] clock {{%.+}}{{.*}} : i4
// CHECK-DAG: [[NEXT]] = comb.mux bin {{%.+}}, {{%.+}}, [[Q]] : i4
// CHECK: hw.output [[Q]] : i4
module top(input logic clk, rst, enable, input logic [3:0] d, output logic [3:0] q);
  logic [3:0] pipe_data [0:1];
  always_comb pipe_data[0] = d;
  always_ff @(posedge clk) begin
    if (rst)
      pipe_data[1] <= '0;
    else if (enable)
      pipe_data[1] <= pipe_data[0];
  end
  always_comb q = pipe_data[1];
endmodule
