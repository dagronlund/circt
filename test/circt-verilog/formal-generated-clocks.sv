// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// REQUIRES: slang

// Keep the falling-edge sample and rising-edge output as separate,
// uninitialized registers on opposite phases of the same clock.
// CHECK-LABEL: hw.module @opposite_edges
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[NEG:%.+]] = seq.clock_inv [[CLK]]
// CHECK: [[HALF:%.+]] = seq.firreg %d clock [[NEG]] : i1
// CHECK-NEXT: [[Q:%.+]] = seq.firreg [[HALF]] clock [[CLK]] : i1
// CHECK-NEXT: hw.output [[Q]] : i1
module opposite_edges(input logic clk, d, output logic q);
  logic half;
  always_ff @(negedge clk) half <= d;
  always_ff @(posedge clk) q <= half;
endmodule

// Both transitions of each projected clock update that lane's counter and
// sample its old high bit into the unpacked output. Saved HW IR hides the
// independent output writes in whole-array process results.
// CHECK-LABEL: hw.module @generated_clocks
// CHECK: [[BIT0:%.+]] = comb.extract %clk from 0 : (i2) -> i1
// CHECK: [[CLK0:%.+]] = seq.to_clock [[BIT0]]
// CHECK: [[NEG0:%.+]] = seq.clock_inv [[CLK0]]
// CHECK: seq.firreg {{.*}} clock [[CLK0]] : i2
// CHECK: seq.firreg {{.*}} clock [[NEG0]] preset 0{{.*}} : i2
// CHECK: seq.firreg {{.*}} clock [[CLK0]]{{.*}} : i1
// CHECK: seq.firreg {{.*}} clock [[NEG0]] preset 0{{.*}} : i1
// CHECK: [[BIT1:%.+]] = comb.extract %clk from 1 : (i2) -> i1
// CHECK: [[CLK1:%.+]] = seq.to_clock [[BIT1]]
// CHECK: [[NEG1:%.+]] = seq.clock_inv [[CLK1]]
// CHECK: seq.firreg {{.*}} clock [[CLK1]] : i2
// CHECK: seq.firreg {{.*}} clock [[NEG1]] preset 0{{.*}} : i2
// CHECK: seq.firreg {{.*}} clock [[CLK1]]{{.*}} : i1
// CHECK: seq.firreg {{.*}} clock [[NEG1]] preset 0{{.*}} : i1
// CHECK: hw.output {{%.+}} : !hw.array<2xi1>
module generated_clocks(input logic [1:0] clk, output logic q [2]);
  for (genvar i = 0; i < 2; i++) begin: gen_clock
    logic [1:0] counter;
    always_ff @(edge clk[i]) begin
      counter <= counter + 2'd1;
      q[i] <= counter[1];
    end
  end
endmodule

// Explicit counter initialization must survive both-edge extraction as well.
// CHECK-LABEL: hw.module @initialized_generated_clocks
// CHECK: seq.firreg {{.*}} preset 0{{.*}} : i2
// CHECK: seq.firreg {{.*}} preset 0{{.*}} : i2
// CHECK: seq.firreg {{.*}} preset 1{{.*}} : i2
// CHECK: seq.firreg {{.*}} preset 0{{.*}} : i2
// CHECK: hw.output {{%.+}} : !hw.array<2xi1>
module initialized_generated_clocks(input logic [1:0] clk,
                                    output logic q [2]);
  for (genvar i = 0; i < 2; i++) begin: gen_clock
    logic [1:0] counter = 2'(i);
    always_ff @(edge clk[i]) begin
      counter <= counter + 2'd1;
      q[i] <= counter[1];
    end
  end
endmodule
