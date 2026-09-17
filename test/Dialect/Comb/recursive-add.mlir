// RUN: circt-opt %s -canonicalize='max-num-rewrites=100 test-convergence=true' | FileCheck %s

// A nested add with a self-referencing input must not repeatedly accumulate
// the inner constant. Such cycles can arise while simplifying unreachable CFGs.
// CHECK-LABEL: hw.module @recursive_add
hw.module @recursive_add(out result : i32) {
  %c1 = hw.constant 1 : i32
  %c2 = hw.constant 2 : i32
  // CHECK: [[INNER:%.+]] = comb.add [[INNER]], %c1_i32 : i32
  %inner = comb.add %inner, %c1 : i32
  // CHECK: [[OUTER:%.+]] = comb.add [[INNER]], %c2_i32 : i32
  %outer = comb.add %inner, %c2 : i32
  // CHECK: hw.output [[OUTER]] : i32
  hw.output %outer : i32
}
