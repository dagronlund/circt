// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// The two-bit loop counter is zero-extended for comparison with the unsized
// bound. Unroll before resolving packed slices and preserve nonblocking write
// order: enabled nibbles override old_data, and disabled reads retain state.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %read_enable : i1, in %write_enable : i2, in %old_data : i8, in %write_data : i8, out q : i8)
// CHECK-DAG: comb.extract %write_enable from 0 : (i2) -> i1
// CHECK-DAG: comb.extract %write_enable from 1 : (i2) -> i1
// CHECK-DAG: comb.extract %write_data from 0 : (i8) -> i4
// CHECK-DAG: comb.extract %write_data from 4 : (i8) -> i4
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: seq.firreg {{.*}} clock [[CLK]]
// CHECK: hw.output {{.*}} : i8
module top(input logic clk, read_enable, input logic [1:0] write_enable,
           input logic [7:0] old_data, write_data, output logic [7:0] q);
  logic [7:0] read_data_reg [0:0];
  always_ff @(posedge clk) begin
    if (read_enable) begin
      read_data_reg[0] <= old_data;
      for (logic [1:0] i = 0; i < 2; i++) begin
        if (write_enable[i]) begin
          read_data_reg[0][i * 4 +: 4] <= write_data[i * 4 +: 4];
        end
      end
    end
  end
  always_comb q = read_data_reg[0];
endmodule
