// RUN: circt-opt --llhd-sig2reg --canonicalize %s | FileCheck %s

// Ignore unchanged feedback bits when promoting immediate drives.
// CHECK-LABEL: hw.module @partial(
// CHECK-NEXT: %[[ZERO3:.*]] = hw.constant 0 : i3
// CHECK-NEXT: %[[ZERO2:.*]] = hw.constant 0 : i2
// CHECK-NEXT: %[[ZERO:.*]] = hw.constant false
// CHECK-NEXT: %[[MID:.*]] = comb.concat %mid, %[[ZERO]] : i2, i1
// CHECK-NEXT: %[[LOW:.*]] = comb.concat %[[ZERO2]], %lo : i2, i1
// CHECK-NEXT: %[[LOWMID:.*]] = comb.or %[[MID]], %[[LOW]] : i3
// CHECK-NEXT: %[[PAD:.*]] = comb.concat %[[ZERO]], %[[LOWMID]] : i1, i3
// CHECK-NEXT: %[[HIGH:.*]] = comb.concat %hi, %[[ZERO3]] : i1, i3
// CHECK-NEXT: %[[RESULT:.*]] = comb.or %[[HIGH]], %[[PAD]] : i4
// CHECK-NEXT: hw.output %[[RESULT]] : i4
hw.module @partial(in %init : i4, in %lo : i1, in %mid : i2, in %hi : i1, out result : i4) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i2
  %three = hw.constant 3 : i2
  %sig = llhd.sig %init : i4
  %low = llhd.sig.extract %sig from %zero : <i4> -> <i1>
  %high = llhd.sig.extract %sig from %three : <i4> -> <i1>
  %read = llhd.prb %sig : i4
  %oldLow = comb.extract %read from 0 : (i4) -> i1
  %oldHigh = comb.extract %read from 3 : (i4) -> i1
  %value = comb.concat %oldHigh, %mid, %oldLow : i1, i2, i1
  llhd.drv %low, %lo after %time : i1
  llhd.drv %high, %hi after %time : i1
  llhd.drv %sig, %value after %time : i4
  hw.output %read : i4
}

// Even a single overlapping bit must prevent promotion.
// CHECK-LABEL: hw.module @overlap(
// CHECK: llhd.sig
// CHECK: llhd.drv
// CHECK: llhd.drv
// CHECK: hw.output
hw.module @overlap(in %init : i1, in %a : i1, in %b : i1, out result : i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %sig = llhd.sig %init : i1
  llhd.drv %sig, %a after %time : i1
  llhd.drv %sig, %b after %time : i1
  %read = llhd.prb %sig : i1
  hw.output %read : i1
}

// A delayed feedback write is not an unchanged combinational bit.
// CHECK-LABEL: hw.module @delayed(
// CHECK: llhd.sig
// CHECK: llhd.drv
// CHECK: llhd.drv
// CHECK: hw.output
hw.module @delayed(in %init : i2, in %a : i1, in %b : i1, out result : i2) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %delay = llhd.constant_time <1ns, 0d, 0e>
  %zero = hw.constant 0 : i1
  %sig = llhd.sig %init : i2
  %low = llhd.sig.extract %sig from %zero : <i2> -> <i1>
  %read = llhd.prb %sig : i2
  %old = comb.extract %read from 0 : (i2) -> i1
  %value = comb.concat %b, %old : i1, i1
  llhd.drv %low, %a after %time : i1
  llhd.drv %sig, %value after %delay : i2
  hw.output %read : i2
}

// Reading a different bit is a real driver, not unchanged feedback.
// CHECK-LABEL: hw.module @different_bit(
// CHECK: llhd.sig
// CHECK: llhd.drv
// CHECK: llhd.drv
// CHECK: hw.output
hw.module @different_bit(in %init : i2, in %a : i1, in %b : i1, out result : i2) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i1
  %sig = llhd.sig %init : i2
  %low = llhd.sig.extract %sig from %zero : <i2> -> <i1>
  %read = llhd.prb %sig : i2
  %old = comb.extract %read from 1 : (i2) -> i1
  %value = comb.concat %b, %old : i1, i1
  llhd.drv %low, %a after %time : i1
  llhd.drv %sig, %value after %time : i2
  hw.output %read : i2
}
