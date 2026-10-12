// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// REQUIRES: slang

// A dynamic read keeps the whole array visible. Ordinary HW lowering pads each
// independent assignment with a probe of the other element; formal lowering
// must recover the partial drives before splitting the array's storage.
// CHECK-LABEL: hw.module @top(in %a : i4, in %b : i4, in %sel : i1
// CHECK: [[DATA:%.+]] = hw.array_create %b, %a : i4
// CHECK-NEXT: [[Q:%.+]] = hw.array_get [[DATA]][%sel] : !hw.array<2xi4>, i1
// CHECK-NEXT: hw.output [[Q]] : i4
module top(input logic [3:0] a, b, input logic sel, output logic [3:0] q);
  logic [1:0][3:0] data;
  always_comb data[0] = a;
  always_comb data[1] = b;
  always_comb q = data[sel];
endmodule

// Ascending packed dimensions reverse the physical ordering of the elements.
// CHECK-LABEL: hw.module @ascending(in %a : i4, in %b : i4, in %sel : i1
// CHECK: [[DATA:%.+]] = hw.array_create %a, %b : i4
// CHECK: [[Q:%.+]] = hw.array_get [[DATA]][{{%.+}}] : !hw.array<2xi4>, i1
// CHECK-NEXT: hw.output [[Q]] : i4
module ascending(input logic [3:0] a, b, input logic sel, output logic [3:0] q);
  logic [0:1][3:0] data;
  always_comb data[0] = a;
  always_comb data[1] = b;
  always_comb q = data[sel];
endmodule

// The same recovery applies to unpacked arrays.
// CHECK-LABEL: hw.module @unpacked(in %a : i4, in %b : i4, in %sel : i1
// CHECK: [[DATA:%.+]] = hw.array_create %b, %a : i4
// CHECK-NEXT: [[Q:%.+]] = hw.array_get [[DATA]][%sel] : !hw.array<2xi4>, i1
// CHECK-NEXT: hw.output [[Q]] : i4
module unpacked(input logic [3:0] a, b, input logic sel, output logic [3:0] q);
  logic [3:0] data [1:0];
  always_comb data[0] = a;
  always_comb data[1] = b;
  always_comb q = data[sel];
endmodule
