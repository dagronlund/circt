// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// REQUIRES: slang

// Either comparison bounds the loop. The tighter condition must still stop it
// after three iterations, and conditional loop-carried writes must retain their
// order. The result counts consecutive set bits starting at bit zero, up to 3.
// CHECK-LABEL: hw.module @top(in %data : i4, out count : i2)
// CHECK: hw.output {{.*}} : i2
module top(input logic [3:0] data, output logic [1:0] count);
  logic searching;
  always_comb begin
    count = '0;
    searching = '1;
    for (logic [31:0] i = 0; i <= 2 && i < 4; i++) begin
      if (searching) begin
        count += data[i];
        searching = data[i];
      end
    end
  end
endmodule

// A data-dependent conjunct must remain a conditional exit in each iteration.
// CHECK-LABEL: hw.module @guarded(in %data : i4, out count : i3)
// CHECK: hw.output {{.*}} : i3
module guarded(input logic [3:0] data, output logic [2:0] count);
  always_comb begin
    count = '0;
    for (logic [31:0] i = 0; i < 4 && data[i]; i++)
      count += 1;
  end
endmodule
