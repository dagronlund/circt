// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset --implicit-check-not=!hw.array
// REQUIRES: slang

// The unpacked array's low element is combinational and only its high element
// is clocked. Ordinary extraction pads the array register with the low element
// in both clear branches. Recover the actual scalar state after HW lowering,
// including when a separate invocation first marks comb ops as two-valued.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %clear : i1, in %cin : i1, in %a : i2, in %b : i2
// CHECK: comb.concat {{.*}}, %cin : i2, i1
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK: [[COUT:%.+]] = seq.firreg {{.*}} clock [[CLK]] {{.*}}: i1
// CHECK-NEXT: [[SUM:%.+]] = seq.firreg {{.*}} clock [[CLK]] : i2
// CHECK-NEXT: hw.output [[SUM]], [[COUT]] : i2, i1
module top(input logic clk, clear, cin, input logic [1:0] a, b,
           output logic [1:0] sum, output logic cout);
  logic carries [1:0];
  assign carries[0] = cin;
  always_ff @(posedge clk) begin
    if (clear) {carries[1], sum} <= '0;
    else {carries[1], sum} <= a + b + carries[0];
  end
  always_comb cout = carries[1];
endmodule
