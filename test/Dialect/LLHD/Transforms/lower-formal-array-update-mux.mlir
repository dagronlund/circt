// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %s --lower-llhd-formal-to-core --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.

// Factor conditional updates to expose a complete injection chain and remove
// apparent feedback. Keep independent conditions and the muxes' flags and attrs.
// CHECK-LABEL: hw.module @independent_conditions
// CHECK-DAG: [[LOW:%.+]] = comb.mux bin %select_low, %a, %b {test.tag = "low"} : i8
// CHECK-DAG: [[HIGH:%.+]] = comb.mux %select_high, %c, %d {test.tag = "high"} : i8
// CHECK-DAG: [[Q:%.+]] = hw.array_create [[HIGH]], [[LOW]] : i8
// CHECK: hw.output [[Q]] : !hw.array<2xi8>
hw.module @independent_conditions(in %select_low: i1, in %select_high: i1, in %a: i8, in %b: i8, in %c: i8, in %d: i8, out q: !hw.array<2xi8>) {
  %zero = hw.constant false
  %one = hw.constant true
  %low_a = hw.array_inject %q[%zero], %a : !hw.array<2xi8>, i1
  %low_b = hw.array_inject %q[%zero], %b : !hw.array<2xi8>, i1
  %low = comb.mux bin %select_low, %low_a, %low_b {test.tag = "low"} : !hw.array<2xi8>
  %high_a = hw.array_inject %low[%one], %c : !hw.array<2xi8>, i1
  %high_b = hw.array_inject %low[%one], %d : !hw.array<2xi8>, i1
  %q = comb.mux %select_high, %high_a, %high_b {test.tag = "high"} : !hw.array<2xi8>
  hw.output %q : !hw.array<2xi8>
}

// Different base arrays must retain their untouched elements on both branches.
// CHECK-LABEL: hw.module @different_bases
// CHECK-DAG: [[LEFT:%.+]] = hw.array_inject %left[%false], %a : !hw.array<2xi8>, i1
// CHECK-DAG: [[RIGHT:%.+]] = hw.array_inject %right[%false], %b : !hw.array<2xi8>, i1
// CHECK: [[Q:%.+]] = comb.mux %select, [[LEFT]], [[RIGHT]] : !hw.array<2xi8>
// CHECK-NEXT: hw.output [[Q]] : !hw.array<2xi8>
hw.module @different_bases(in %select: i1, in %left: !hw.array<2xi8>, in %right: !hw.array<2xi8>, in %a: i8, in %b: i8, out q: !hw.array<2xi8>) {
  %zero = hw.constant false
  %left_update = hw.array_inject %left[%zero], %a : !hw.array<2xi8>, i1
  %right_update = hw.array_inject %right[%zero], %b : !hw.array<2xi8>, i1
  %q = comb.mux %select, %left_update, %right_update : !hw.array<2xi8>
  hw.output %q : !hw.array<2xi8>
}

// Equal base arrays with different indices still update different elements.
// CHECK-LABEL: hw.module @different_indices
// CHECK-DAG: [[LEFT:%.+]] = hw.array_inject %base[%false], %a : !hw.array<2xi8>, i1
// CHECK-DAG: [[RIGHT:%.+]] = hw.array_inject %base[%true], %b : !hw.array<2xi8>, i1
// CHECK: [[Q:%.+]] = comb.mux %select, [[LEFT]], [[RIGHT]] : !hw.array<2xi8>
// CHECK-NEXT: hw.output [[Q]] : !hw.array<2xi8>
hw.module @different_indices(in %select: i1, in %base: !hw.array<2xi8>, in %a: i8, in %b: i8, out q: !hw.array<2xi8>) {
  %zero = hw.constant false
  %one = hw.constant true
  %left_update = hw.array_inject %base[%zero], %a : !hw.array<2xi8>, i1
  %right_update = hw.array_inject %base[%one], %b : !hw.array<2xi8>, i1
  %q = comb.mux %select, %left_update, %right_update : !hw.array<2xi8>
  hw.output %q : !hw.array<2xi8>
}
