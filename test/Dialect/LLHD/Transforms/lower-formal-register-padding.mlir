// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-opt %s --lower-llhd-formal-to-core --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset

// Split wider packed lanes, preserving the actual state and its attributes.
// CHECK-LABEL: hw.module @padding
// CHECK: [[Q:%.+]] = seq.firreg %high clock %clk {test.tag = "state"} : i5
// CHECK-NEXT: hw.output [[Q]] : i5
hw.module @padding(in %clk: !seq.clock, in %low: i3, in %high: i5, out q: i5) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i8
  %index = hw.constant 0 : i3
  %s = llhd.sig %zero {llhd.unconstrained} : i8
  %low_ref = llhd.sig.extract %s from %index : <i8> -> <i3>
  llhd.drv %low_ref, %low after %time : i3
  %value = llhd.prb %s : i8
  %old_low = comb.extract %value from 0 : (i8) -> i3
  %next = comb.concat %high, %old_low : i5, i3
  %reg = seq.firreg %next clock %clk {test.tag = "state"} : i8
  llhd.drv %s, %reg after %time : i8
  %q = comb.extract %value from 3 : (i8) -> i5
  hw.output %q : i5
}
