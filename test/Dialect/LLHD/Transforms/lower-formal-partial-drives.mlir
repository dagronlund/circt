// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %s --lower-llhd-formal-to-core --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.

// Recover whole-field drives, then the independent bits inside b. Different
// values in every field check that the recovered targets preserve their order.
// CHECK-LABEL: hw.module @struct_fields
// CHECK: [[B:%.+]] = comb.concat %high, %low : i1, i1
// CHECK-NEXT: [[Q:%.+]] = hw.struct_create (%a, [[B]], %c) : !hw.struct<a: i1, b: i2, c: i2>
// CHECK-NEXT: hw.output [[Q]] : !hw.struct<a: i1, b: i2, c: i2>
hw.module @struct_fields(in %a: i1, in %low: i1, in %high: i1, in %c: i2, out q: !hw.struct<a: i1, b: i2, c: i2>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [false, 0 : i2, 0 : i2] : !hw.struct<a: i1, b: i2, c: i2>
  %s = llhd.sig %init {llhd.unconstrained} : !hw.struct<a: i1, b: i2, c: i2>
  %old = llhd.prb %s : !hw.struct<a: i1, b: i2, c: i2>
  %a_next = hw.struct_inject %old["a"], %a : !hw.struct<a: i1, b: i2, c: i2>
  %c_next = hw.struct_inject %old["c"], %c : !hw.struct<a: i1, b: i2, c: i2>
  %b_old = hw.struct_extract %old["b"] : !hw.struct<a: i1, b: i2, c: i2>
  %old_low = comb.extract %b_old from 0 : (i2) -> i1
  %old_high = comb.extract %b_old from 1 : (i2) -> i1
  %low_word = comb.concat %old_high, %low : i1, i1
  %high_word = comb.concat %high, %old_low : i1, i1
  %low_next = hw.struct_inject %old["b"], %low_word : !hw.struct<a: i1, b: i2, c: i2>
  %high_next = hw.struct_inject %old["b"], %high_word : !hw.struct<a: i1, b: i2, c: i2>
  llhd.drv %s, %a_next after %time : !hw.struct<a: i1, b: i2, c: i2>
  llhd.drv %s, %low_next after %time : !hw.struct<a: i1, b: i2, c: i2>
  llhd.drv %s, %high_next after %time : !hw.struct<a: i1, b: i2, c: i2>
  llhd.drv %s, %c_next after %time : !hw.struct<a: i1, b: i2, c: i2>
  hw.output %old : !hw.struct<a: i1, b: i2, c: i2>
}

// Preserve wider packed lanes rather than splitting every bit.
// CHECK-LABEL: hw.module @packed_lanes
// CHECK: [[Q:%.+]] = comb.concat %high, %low : i5, i3
// CHECK-NEXT: hw.output [[Q]] : i8
hw.module @packed_lanes(in %low: i3, in %high: i5, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.constant 0 : i8
  %s = llhd.sig %init {llhd.unconstrained} : i8
  %old = llhd.prb %s : i8
  %old_low = comb.extract %old from 0 : (i8) -> i3
  %old_high = comb.extract %old from 3 : (i8) -> i5
  %low_next = comb.concat %old_high, %low : i5, i3
  %high_next = comb.concat %high, %old_low : i5, i3
  llhd.drv %s, %low_next after %time : i8
  llhd.drv %s, %high_next after %time : i8
  hw.output %old : i8
}
