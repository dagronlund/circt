// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=sim. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=sim. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=sim. --implicit-check-not=preset
// REQUIRES: slang

// Dropping the formatted message must not drop evaluation effects in its
// arguments. Retain the counter update as state as well as the failing check.
// CHECK-LABEL: hw.module @top(
// CHECK: [[INCREMENT:%.+]] = comb.add [[COUNT:%.+]], {{%.+}} : i8
// CHECK: verif.clocked_assert {{.*}}, posedge %clk
// CHECK: [[NEXT:%.+]] = comb.mux bin {{%.+}}, [[COUNT]], [[INCREMENT]] : i8
// CHECK: [[COUNT]] = seq.firreg [[NEXT]] clock {{%.+}} : i8
// CHECK-NEXT: hw.output [[COUNT]] : i8
module top(input logic clk, enable, ok, output logic [7:0] count);
  always @(posedge clk)
    if (enable)
      assert (ok) else $error("Assertion failed: count=%0d", count++);
endmodule
