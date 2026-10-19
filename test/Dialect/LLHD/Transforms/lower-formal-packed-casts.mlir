// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %s --lower-llhd-formal-to-core --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.

// A truncating packed cast observes only the driven low bits of one element.
// CHECK-LABEL: hw.module @Truncated
// CHECK-NEXT: hw.output %data : i3
hw.module @Truncated(in %data: i3, out q: i3) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [0 : i8] : !hw.array<1xi8>
  %index = hw.constant 0 : i0
  %low = hw.constant 0 : i3
  %s = llhd.sig %init {llhd.unconstrained} : !hw.array<1xi8>
  %element = llhd.sig.array_get %s[%index] : <!hw.array<1xi8>>
  %bits = llhd.sig.extract %element from %low : <i8> -> <i3>
  llhd.drv %bits, %data after %time : i3
  %value = llhd.prb %s : !hw.array<1xi8>
  %packed = hw.bitcast %value : (!hw.array<1xi8>) -> i8
  %q = comb.extract %packed from 0 : (i8) -> i3
  hw.output %q : i3
}

// Preserve the packing order across element boundaries. The third element is
// undriven and entirely outside the observed twelve-bit interval.
// CHECK-LABEL: hw.module @AcrossElements
// CHECK: [[HIGH:%.+]] = comb.extract %a from 4 : (i8) -> i4
// CHECK: [[Q:%.+]] = comb.concat %b, [[HIGH]] : i8, i4
// CHECK-NEXT: hw.output [[Q]] : i12
hw.module @AcrossElements(in %a: i8, in %b: i8, out q: i12) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [0 : i8, 0 : i8, 0 : i8] : !hw.array<3xi8>
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %s = llhd.sig %init {llhd.unconstrained} : !hw.array<3xi8>
  %low = llhd.sig.array_get %s[%zero] : <!hw.array<3xi8>>
  %high = llhd.sig.array_get %s[%one] : <!hw.array<3xi8>>
  llhd.drv %low, %a after %time : i8
  llhd.drv %high, %b after %time : i8
  %value = llhd.prb %s : !hw.array<3xi8>
  %packed = hw.bitcast %value : (!hw.array<3xi8>) -> i24
  %q = comb.extract %packed from 4 : (i24) -> i12
  hw.output %q : i12
}

// Recursively expose nested array construction, retaining outer/inner order.
// CHECK-LABEL: hw.module @Nested
// CHECK-NEXT: hw.output %data : i4
hw.module @Nested(in %data: i4, out q: i4) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [[0 : i4, 0 : i4], [0 : i4, 0 : i4]] : !hw.array<2xarray<2xi4>>
  %zero = hw.constant false
  %one = hw.constant true
  %s = llhd.sig %init {llhd.unconstrained} : !hw.array<2xarray<2xi4>>
  %row = llhd.sig.array_get %s[%one] : <!hw.array<2xarray<2xi4>>>
  %element = llhd.sig.array_get %row[%zero] : <!hw.array<2xi4>>
  llhd.drv %element, %data after %time : i4
  %value = llhd.prb %s : !hw.array<2xarray<2xi4>>
  %packed = hw.bitcast %value : (!hw.array<2xarray<2xi4>>) -> i16
  %q = comb.extract %packed from 8 : (i16) -> i4
  hw.output %q : i4
}
