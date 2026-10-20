// RUN: circt-opt %s --llhd-unroll-loops --verif-abstract-random | FileCheck %s --implicit-check-not=__circt_urandom_range

// Use the existing upstream loop unroller explicitly; the abstraction pass
// itself does not unroll or restructure control flow.
func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
// CHECK-LABEL: hw.module @unrolled(
// CHECK-COUNT-3: verif.symbolic_value : i32
// CHECK: llhd.combinational -> i32
// CHECK-COUNT-3: comb.add
// CHECK: llhd.yield
hw.module @unrolled(out value: i32) {
  %zero = hw.constant 0 : i32
  %one = hw.constant 1 : i32
  %three = hw.constant 3 : i32
  %max = hw.constant -1 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %value = llhd.combinational -> i32 {
    cf.br ^header(%zero, %zero : i32, i32)
  ^header(%i: i32, %sum: i32):
    %continue = comb.icmp ult %i, %three : i32
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %draw = func.call @__circt_urandom_range(%zero, %max, %null) : (i32, i32, !llvm.ptr) -> i32
    %next_sum = comb.add %sum, %draw : i32
    %next_i = comb.add %i, %one : i32
    cf.br ^header(%next_i, %next_sum : i32, i32)
  ^exit:
    llhd.yield %sum : i32
  }
  hw.output %value : i32
}
