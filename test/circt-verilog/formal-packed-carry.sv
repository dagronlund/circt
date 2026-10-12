// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// Ordinary HW lowering pads the clocked carry update with the unchanged low
// bit. Formal lowering must recover its independent combinational driver.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %clear : i1, in %cin : i1, in %a : i2, in %b : i2
// CHECK-DAG: [[TRUE:%.+]] = hw.constant true
// CHECK-DAG: [[ZERO:%.+]] = hw.constant 0 : i2
// CHECK-DAG: [[FALSE:%.+]] = hw.constant false
// CHECK-DAG: [[A:%.+]] = comb.concat [[FALSE]], %a : i1, i2
// CHECK-DAG: [[B:%.+]] = comb.concat [[FALSE]], %b : i1, i2
// CHECK-DAG: [[CIN:%.+]] = comb.concat [[ZERO]], %cin : i2, i1
// CHECK-DAG: [[ADD:%.+]] = comb.add [[A]], [[B]], [[CIN]] : i3
// CHECK-DAG: [[CARRY:%.+]] = comb.extract [[ADD]] from 2 : (i3) -> i1
// CHECK-DAG: [[SUM:%.+]] = comb.extract [[ADD]] from 0 : (i3) -> i2
// CHECK-DAG: [[EN:%.+]] = comb.xor %clear, [[TRUE]] : i1
// CHECK-DAG: [[NEXT_CARRY:%.+]] = comb.and [[EN]], [[CARRY]] : i1
// CHECK-DAG: [[NEXT_SUM:%.+]] = comb.mux [[EN]], [[SUM]], [[ZERO]] : i2
// CHECK: [[CLK:%.+]] = seq.to_clock %clk
// CHECK-NEXT: [[COUT:%.+]] = seq.firreg [[NEXT_CARRY]] clock [[CLK]] {{.*}}: i1
// CHECK-NEXT: [[Q:%.+]] = seq.firreg [[NEXT_SUM]] clock [[CLK]] : i2
// CHECK-NEXT: hw.output [[Q]], [[COUT]] : i2, i1
module top(input logic clk, clear, cin, input logic [1:0] a, b,
           output logic [1:0] sum, output logic cout);
  logic [1:0] carries;
  assign carries[0] = cin;
  always_ff @(posedge clk) begin
    if (clear) {carries[1], sum} <= '0;
    else {carries[1], sum} <= a + b + carries[0];
  end
  always_comb cout = carries[1];
endmodule
