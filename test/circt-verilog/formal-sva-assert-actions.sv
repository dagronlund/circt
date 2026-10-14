// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=ltl.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=ltl.
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=ltl.
// REQUIRES: slang

// Literal and formatted failure actions must preserve next-cycle sampling,
// overlapping attempts, and the absence of a pending attempt at startup.
// CHECK-LABEL: hw.module @sva_literal_delayed(
// CHECK-NEXT: [[CLK:%.+]] = seq.to_clock %clk
// CHECK-NEXT: [[PENDING:%.+]] = seq.firreg %enable clock [[CLK]] preset 0 : i1
// CHECK-NEXT: verif.clocked_assert %ok if [[PENDING]], posedge %clk : i1
// CHECK-NEXT: hw.output
module sva_literal_delayed(input logic clk, enable, ok,
                           input logic [7:0] value);
  assert property (@(posedge clk) enable |=> ok)
    else $error("Assertion failed");
endmodule

// CHECK-LABEL: hw.module @sva_formatted_delayed(
// CHECK-NEXT: [[CLK:%.+]] = seq.to_clock %clk
// CHECK-NEXT: [[PENDING:%.+]] = seq.firreg %enable clock [[CLK]] preset 0 : i1
// CHECK-NEXT: verif.clocked_assert %ok if [[PENDING]], posedge %clk : i1
// CHECK-NEXT: hw.output
module sva_formatted_delayed(input logic clk, enable, ok,
                             input logic [7:0] value);
  assert property (@(posedge clk) enable |=> ok)
    else $error("Assertion failed: value=%0d", value);
endmodule
