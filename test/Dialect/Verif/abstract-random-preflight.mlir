// RUN: not circt-opt %s --verif-abstract-random --mlir-print-ir-after-failure 2>&1 | FileCheck %s --implicit-check-not=verif.symbolic_value

// A later error must leave earlier supported calls untouched.
// CHECK: error: random call may execute repeatedly
// CHECK: IR Dump After
// CHECK: hw.module @supported(
// CHECK: func.call @__circt_urandom_range
// CHECK: hw.module @unsupported(
// CHECK: func.call @__circt_urandom_range
func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
hw.module @supported(out value: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %draw = func.call @__circt_urandom_range(%zero, %max, %null) : (i32, i32, !llvm.ptr) -> i32
  hw.output %draw : i32
}
hw.module @unsupported(in %again: i1, out value: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %value = llhd.combinational -> i32 {
    cf.br ^body
  ^body:
    %draw = func.call @__circt_urandom_range(%zero, %max, %null) : (i32, i32, !llvm.ptr) -> i32
    cf.cond_br %again, ^body, ^exit
  ^exit:
    llhd.yield %draw : i32
  }
  hw.output %value : i32
}
