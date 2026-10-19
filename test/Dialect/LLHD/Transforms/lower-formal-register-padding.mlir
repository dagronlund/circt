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

// The unchanged element is common to both mux arms. Project the written array
// element through the mux, preserving its twoState flag and arbitrary attrs.
// CHECK-LABEL: hw.module @array_padding
// CHECK: [[NEXT:%.+]] = comb.mux bin %sel, %a, %b {test.tag = "mux"} : i3
// CHECK: [[Q:%.+]] = seq.firreg [[NEXT]] clock %clk {test.tag = "state"} : i3
// CHECK-NEXT: hw.output [[Q]] : i3
hw.module @array_padding(in %clk: !seq.clock, in %sel: i1, in %low: i3, in %a: i3, in %b: i3, out q: i3) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.aggregate_constant [0 : i3, 0 : i3] : !hw.array<2xi3>
  %false = hw.constant false
  %true = hw.constant true
  %s = llhd.sig %zero {llhd.unconstrained} : !hw.array<2xi3>
  %low_ref = llhd.sig.array_get %s[%false] : !llhd.ref<!hw.array<2xi3>>
  llhd.drv %low_ref, %low after %time : i3
  %value = llhd.prb %s : !hw.array<2xi3>
  %old_low = hw.array_get %value[%false] : !hw.array<2xi3>, i1
  %a_next = hw.array_create %a, %old_low : i3
  %b_next = hw.array_inject %value[%true], %b : !hw.array<2xi3>, i1
  %next = comb.mux bin %sel, %a_next, %b_next {test.tag = "mux"} : !hw.array<2xi3>
  %reg = seq.firreg %next clock %clk {test.tag = "state"} : !hw.array<2xi3>
  llhd.drv %s, %reg after %time : !hw.array<2xi3>
  %q = hw.array_get %value[%true] : !hw.array<2xi3>, i1
  hw.output %q : i3
}

// Project an enabled array register's self-feedback separately for each lane.
// A hold on the true arm must retain its polarity, flags, and attributes.
// CHECK-LABEL: hw.module @enabled_array_padding
// CHECK: [[Q:%.+]] = seq.firreg [[NEXT:%.+]] clock %clk {test.tag = "state"} : i3
// CHECK-NEXT: [[NEXT]] = comb.mux bin %hold, [[Q]], %high {test.tag = "hold"} : i3
// CHECK-NEXT: hw.output [[Q]] : i3
hw.module @enabled_array_padding(in %clk: !seq.clock, in %hold: i1, in %low: i3, in %high: i3, out q: i3) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.aggregate_constant [0 : i3, 0 : i3] : !hw.array<2xi3>
  %false = hw.constant false
  %true = hw.constant true
  %s = llhd.sig %zero {llhd.unconstrained} : !hw.array<2xi3>
  %low_ref = llhd.sig.array_get %s[%false] : !llhd.ref<!hw.array<2xi3>>
  llhd.drv %low_ref, %low after %time : i3
  %value = llhd.prb %s : !hw.array<2xi3>
  %update = hw.array_inject %value[%true], %high : !hw.array<2xi3>, i1
  %next = comb.mux bin %hold, %reg, %update {test.tag = "hold"} : !hw.array<2xi3>
  %reg = seq.firreg %next clock %clk {test.tag = "state"} : !hw.array<2xi3>
  llhd.drv %s, %reg after %time : !hw.array<2xi3>
  %q = hw.array_get %value[%true] : !hw.array<2xi3>, i1
  hw.output %q : i3
}

// Packed lanes also retain scalar feedback and four-state mux semantics.
// CHECK-LABEL: hw.module @enabled_packed_padding
// CHECK: [[Q:%.+]] = seq.firreg [[NEXT:%.+]] clock %clk : i5
// CHECK-NEXT: [[NEXT]] = comb.mux %en, %high, [[Q]] {test.tag = "hold"} : i5
// CHECK-NEXT: hw.output [[Q]] : i5
hw.module @enabled_packed_padding(in %clk: !seq.clock, in %en: i1, in %low: i3, in %high: i5, out q: i5) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i8
  %index = hw.constant 0 : i3
  %s = llhd.sig %zero {llhd.unconstrained} : i8
  %low_ref = llhd.sig.extract %s from %index : <i8> -> <i3>
  llhd.drv %low_ref, %low after %time : i3
  %value = llhd.prb %s : i8
  %old_low = comb.extract %value from 0 : (i8) -> i3
  %update = comb.concat %high, %old_low : i5, i3
  %next = comb.mux %en, %update, %reg {test.tag = "hold"} : i8
  %reg = seq.firreg %next clock %clk : i8
  llhd.drv %s, %reg after %time : i8
  %q = comb.extract %value from 3 : (i8) -> i5
  hw.output %q : i5
}

// No signal projections survive ordinary extraction. Recover the wider packed
// lane boundaries from the concatenations, without splitting every bit.
// CHECK-LABEL: hw.module @whole_packed_drives
// CHECK-DAG: [[LOW:%.+]] = seq.firreg %low clock %clk {test.tag = "low"} : i3
// CHECK-DAG: [[HIGH:%.+]] = seq.firreg %high clock %clk {test.tag = "high"} : i5
// CHECK-DAG: [[Q:%.+]] = comb.concat [[HIGH]], [[LOW]] : i5, i3
// CHECK: hw.output [[Q]] : i8
hw.module @whole_packed_drives(in %clk: !seq.clock, in %low: i3, in %high: i5, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i8
  %s = llhd.sig %zero {llhd.unconstrained} : i8
  %old = llhd.prb %s : i8
  %old_low = comb.extract %old from 0 : (i8) -> i3
  %old_high = comb.extract %old from 3 : (i8) -> i5
  %low_next = comb.concat %old_high, %low : i5, i3
  %high_next = comb.concat %high, %old_low : i5, i3
  %low_reg = seq.firreg %low_next clock %clk {test.tag = "low"} : i8
  %high_reg = seq.firreg %high_next clock %clk {test.tag = "high"} : i8
  llhd.drv %s, %low_reg after %time : i8
  llhd.drv %s, %high_reg after %time : i8
  hw.output %old : i8
}

// Enabled updates hide the concatenations behind self-feedback muxes. Keep
// each lane's enable, attributes, and unconstrained initial state.
// CHECK-LABEL: hw.module @enabled_whole_packed_drives
// CHECK-DAG: [[LOW:%.+]] = seq.firreg [[LOW_NEXT:%.+]] clock %clk {test.tag = "low"} : i3
// CHECK-DAG: [[LOW_NEXT]] = comb.mux bin %enable_low, %low, [[LOW]] : i3
// CHECK-DAG: [[HIGH:%.+]] = seq.firreg [[HIGH_NEXT:%.+]] clock %clk {test.tag = "high"} : i5
// CHECK-DAG: [[HIGH_NEXT]] = comb.mux %enable_high, %high, [[HIGH]] : i5
// CHECK-DAG: [[Q:%.+]] = comb.concat [[HIGH]], [[LOW]] : i5, i3
// CHECK: hw.output [[Q]] : i8
hw.module @enabled_whole_packed_drives(in %clk: !seq.clock, in %enable_low: i1, in %enable_high: i1, in %low: i3, in %high: i5, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i8
  %s = llhd.sig %zero {llhd.unconstrained} : i8
  %old = llhd.prb %s : i8
  %old_low = comb.extract %old from 0 : (i8) -> i3
  %old_high = comb.extract %old from 3 : (i8) -> i5
  %low_update = comb.concat %old_high, %low : i5, i3
  %high_update = comb.concat %high, %old_low : i5, i3
  %low_next = comb.mux bin %enable_low, %low_update, %low_reg : i8
  %high_next = comb.mux %enable_high, %high_update, %high_reg : i8
  %low_reg = seq.firreg %low_next clock %clk {test.tag = "low"} : i8
  %high_reg = seq.firreg %high_next clock %clk {test.tag = "high"} : i8
  llhd.drv %s, %low_reg after %time : i8
  llhd.drv %s, %high_reg after %time : i8
  hw.output %old : i8
}
