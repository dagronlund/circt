// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// REQUIRES: slang

// Sharing k + 1 with the increment lets CFG cleanup bypass the latch on the
// false branch. Both paths return to the header with the same next counter,
// but different output values. The second iteration's write takes priority.
// CHECK-LABEL: hw.module @top(in %a : i3, in %b : i3, out x : i1, out y : i2)
// CHECK: [[ZERO:%.+]] = hw.constant 0 : i2
// CHECK: [[A0:%.+]] = comb.extract %a from 0 : (i3) -> i1
// CHECK: [[A1:%.+]] = comb.extract %a from 1 : (i3) -> i1
// CHECK: [[LOW:%.+]] = comb.and{{( bin)?}} [[A0]], [[A1]] : i1
// CHECK: [[B01:%.+]] = comb.extract %b from 0 : (i3) -> i2
// CHECK: [[FIRST:%.+]] = comb.mux{{( bin)?}} [[LOW]], [[B01]], [[ZERO]] : i2
// CHECK: [[A2:%.+]] = comb.extract %a from 2 : (i3) -> i1
// CHECK: [[HIGH:%.+]] = comb.and{{( bin)?}} [[A1]], [[A2]] : i1
// CHECK: [[B12:%.+]] = comb.extract %b from 1 : (i3) -> i2
// CHECK: [[X:%.+]] = comb.or{{( bin)?}} [[HIGH]], [[LOW]] : i1
// CHECK: [[Y:%.+]] = comb.mux{{( bin)?}} [[HIGH]], [[B12]], [[FIRST]] : i2
// CHECK-NEXT: hw.output [[X]], [[Y]] : i1, i2
module top(input logic [2:0] a, b, output logic x, output logic [1:0] y);
  always_comb begin
    x = 0;
    y = 0;
    for (logic signed [31:0] k = 0; k < 2; k++) begin
      if (a[k] && a[k + 1]) begin
        x = 1;
        y = {b[k + 1], b[k]};
      end
    end
  end
endmodule
