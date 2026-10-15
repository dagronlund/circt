// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// REQUIRES: slang

// A statically unrolled initial loop defines a ROM of nested packed words.
// Preserve the ascending unpacked index order and all four computed contents.
// CHECK-LABEL: hw.module @top(in %address : i2
// CHECK-DAG: [[WORD0:%.+]] = hw.aggregate_constant [0 : i4, 1 : i4] : !hw.array<2xi4>
// CHECK-DAG: [[WORD1:%.+]] = hw.aggregate_constant [0 : i4, 2 : i4] : !hw.array<2xi4>
// CHECK-DAG: [[WORD2:%.+]] = hw.aggregate_constant [0 : i4, 5 : i4] : !hw.array<2xi4>
// CHECK-DAG: [[WORD3:%.+]] = hw.aggregate_constant [0 : i4, -6 : i4] : !hw.array<2xi4>
// CHECK-DAG: [[LAST:%.+]] = hw.constant -1 : i2
// CHECK: [[ROM:%.+]] = hw.array_create [[WORD0]], [[WORD1]], [[WORD2]], [[WORD3]] : !hw.array<2xi4>
// CHECK: [[INDEX:%.+]] = comb.sub {{(bin )?}}[[LAST]], %address : i2
// CHECK-NEXT: [[Q:%.+]] = hw.array_get [[ROM]][[[INDEX]]] : !hw.array<4xarray<2xi4>>, i2
// CHECK-NEXT: hw.output [[Q]] : !hw.array<2xi4>
module top(input logic [1:0] address, output logic [1:0][3:0] q);
  typedef logic [1:0][3:0] word_t;
  word_t rom [0:3];
  initial begin
    for (logic [2:0] i = 0; i < 4; i++) begin
      rom[i] = word_t'(i * i + 1);
    end
  end
  always_comb q = rom[address];
endmodule
