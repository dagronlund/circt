// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// Ordinary extraction wraps each packed bit update in a whole-array register.
// Splitting the outer array must continue into its integer element, even when
// neither register has a whole array element of passthrough padding.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %rst : i1, in %d : i2
// CHECK-DAG: [[TRUE:%.+]] = hw.constant true
// CHECK-DAG: [[NOT_RST:%.+]] = comb.xor{{( bin)?}} %rst, [[TRUE]] : i1
// CHECK-DAG: [[D0:%.+]] = comb.extract %d from 0 : (i2) -> i1
// CHECK-DAG: [[D1:%.+]] = comb.extract %d from 1 : (i2) -> i1
// CHECK-DAG: [[NEXT0:%.+]] = comb.and{{( bin)?}} [[NOT_RST]], [[D0]] : i1
// CHECK-DAG: [[NEXT1:%.+]] = comb.and{{( bin)?}} [[NOT_RST]], [[D1]] : i1
// CHECK-DAG: [[CLK:%.+]] = seq.to_clock %clk
// CHECK-DAG: [[Q0:%.+]] = seq.firreg [[NEXT0]] clock [[CLK]] {{.*}}: i1
// CHECK-DAG: [[Q1:%.+]] = seq.firreg [[NEXT1]] clock [[CLK]] {{.*}}: i1
// CHECK: [[WORD:%.+]] = comb.concat [[Q1]], [[Q0]] : i1, i1
// CHECK-NEXT: [[Q:%.+]] = hw.array_create [[WORD]] : i2
// CHECK-NEXT: hw.output [[Q]] : !hw.array<1xi2>
module top(input logic clk, rst, input logic [1:0] d,
           output logic [0:0][1:0] q);
  logic [0:0][1:0] state;
  for (genvar i = 0; i < 2; i++) begin: gen_state
    always_ff @(posedge clk) begin
      if (rst)
        state[0][i] <= 1'b0;
      else
        state[0][i] <= d[i];
    end
  end
  always_comb q = state;
endmodule

// Recurse through two array dimensions and retain each bit's enable feedback.
// CHECK-LABEL: hw.module @nested_enabled
// CHECK-COUNT-4: seq.firreg {{.*}} : i1
// CHECK-NOT: seq.firreg
// CHECK: hw.output {{%.+}} : !hw.array<2xarray<1xi2>>
module nested_enabled(input logic clk, input logic [1:0][1:0] enable, d,
                      output logic [1:0][0:0][1:0] q);
  logic [1:0][0:0][1:0] state;
  for (genvar j = 0; j < 2; j++) begin: gen_word
    for (genvar i = 0; i < 2; i++) begin: gen_bit
      always_ff @(posedge clk)
        if (enable[j][i])
          state[j][0][i] <= d[j][i];
    end
  end
  always_comb q = state;
endmodule
