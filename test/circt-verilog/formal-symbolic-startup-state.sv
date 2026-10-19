// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// REQUIRES: slang

// Sample the startup input against the declaration initializer. Constrain the
// otherwise uninitialized state only before its first edge, independently of
// enable. Later changes to init_value must not constrain the feedback register.
// CHECK-LABEL: hw.module @top(in %clk : i1, in %enable : i1, in %init_value : i8
// CHECK-DAG: [[ONE:%.+]] = hw.constant 1 : i8
// CHECK-DAG: [[FALSE:%.+]] = hw.constant false
// CHECK-DAG: [[INITIAL:%.+]] = comb.xor {{(bin )?}}%init_value, [[ONE]] : i8
// CHECK-DAG: [[CLK:%.+]] = seq.to_clock %clk
// CHECK-DAG: [[STARTUP:%.+]] = seq.firreg [[FALSE]] clock [[CLK]] preset 1 : i1
// CHECK-DAG: [[STATE:%.+]] = seq.firreg [[NEXT:%.+]] clock [[CLK]] {{(\{name = "seed"\} )?}}: i8
// CHECK-DAG: [[NEXT]] = comb.mux bin %enable, {{%.+}}, [[STATE]] : i8
// CHECK-DAG: [[EQUAL:%.+]] = comb.icmp {{(bin )?}}eq [[STATE]], [[INITIAL]] : i8
// CHECK-DAG: [[INACTIVE:%.+]] = comb.xor [[STARTUP]], {{%.+}} : i1
// CHECK-DAG: [[CONSTRAINT:%.+]] = comb.or [[INACTIVE]], [[EQUAL]] : i1
// CHECK-DAG: verif.assume [[CONSTRAINT]] : i1
// CHECK: hw.output [[STATE]] : i8
module top(input logic clk, enable, input bit [7:0] init_value,
           output logic [7:0] q);
  bit [7:0] seed = 8'h01;
  initial seed = seed ^ init_value;
  always @(posedge clk)
    if (enable) seed <= {seed[6:0], seed[7] ^ seed[5]};
  always_comb q = seed;
endmodule
