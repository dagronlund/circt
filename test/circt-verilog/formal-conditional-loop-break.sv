// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// REQUIRES: slang

// The signed loop executes once whenever enabled, regardless of the break.
// CFG cleanup turns the final choice of 1 or 0 into an Arith zero extension.
// CHECK-LABEL: hw.module @top(in %enable : i1, in %eop : i1, out produce : i32)
// CHECK: [[ZERO:%.+]] = hw.constant 0 : i31
// CHECK: [[PRODUCE:%.+]] = comb.concat [[ZERO]], %enable : i31, i1
// CHECK-NEXT: hw.output [[PRODUCE]] : i32
module top(input logic enable, eop, output logic [31:0] produce);
  always_comb begin
    produce = '0;
    if (enable) begin
      for (logic signed [31:0] i = 0; i < 1; i++) begin
        produce = i + 1;
        if (eop) break;
      end
    end
  end
endmodule

// Reversing the constants can also introduce an Arith Boolean inversion.
// CHECK-LABEL: hw.module @inverted(in %enable : i1, in %eop : i1, out produce : i32)
// CHECK-DAG: [[ZERO:%.+]] = hw.constant 0 : i31
// CHECK-DAG: [[TRUE:%.+]] = hw.constant true
// CHECK: [[INVERTED:%.+]] = comb.xor %enable, [[TRUE]] : i1
// CHECK: [[PRODUCE:%.+]] = comb.concat [[ZERO]], [[INVERTED]] : i31, i1
// CHECK-NEXT: hw.output [[PRODUCE]] : i32
module inverted(input logic enable, eop, output logic [31:0] produce);
  always_comb begin
    produce = 1;
    if (enable) begin
      for (logic signed [31:0] i = 0; i < 1; i++) begin
        produce = i;
        if (eop) break;
      end
    end
  end
endmodule
