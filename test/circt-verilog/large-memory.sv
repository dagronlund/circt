// RUN: circt-verilog %s --ir-hw | FileCheck %s
// REQUIRES: slang

// The default initializer must not flatten this array into an i16777216,
// which exceeds MLIR's maximum integer bit width.
// CHECK-LABEL: hw.module @top(
// CHECK: [[INIT:%.+]] = hw.aggregate_constant [0 : i32,
// CHECK-SAME: : !hw.array<524288xi32>
// CHECK: [[MEM:%.+]] = llhd.sig [[INIT]] : !hw.array<524288xi32>
// CHECK: [[READ:%.+]] = llhd.prb [[MEM]] : !hw.array<524288xi32>
// CHECK: [[RESULT:%.+]] = hw.array_get [[READ]][{{%.+}}] : !hw.array<524288xi32>, i19
// CHECK: hw.output [[RESULT]] : i32
module top(input bit [18:0] addr, output bit [31:0] result);
  bit [31:0] mem [524288];
  assign result = mem[addr];
endmodule
