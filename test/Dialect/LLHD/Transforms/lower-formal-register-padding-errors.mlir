// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

// A genuine overlapping write is not passthrough padding.
hw.module @changed_lane(in %clk: !seq.clock, in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i2
  %low_index = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : i2
  %low = llhd.sig.extract %s from %low_index : <i2> -> <i1>
  llhd.drv %low, %a after %time : i1
  %next = comb.concat %a, %b : i1, i1
  %reg = seq.firreg %next clock %clk : i2
  llhd.drv %s, %reg after %time : i2
  hw.output
}

// -----

// A preset gives the copied-through lane actual initial state.
hw.module @preset_lane(in %clk: !seq.clock, in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i2
  %low_index = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : i2
  %low = llhd.sig.extract %s from %low_index : <i2> -> <i1>
  llhd.drv %low, %a after %time : i1
  %value = llhd.prb %s : i2
  %old_low = comb.extract %value from 0 : (i2) -> i1
  %next = comb.concat %b, %old_low : i1, i1
  %reg = seq.firreg %next clock %clk preset 3 : i2
  llhd.drv %s, %reg after %time : i2
  hw.output
}

// -----

// Resetting a lane is an actual write, even if its next input passes it through.
hw.module @reset_lane(in %clk: !seq.clock, in %rst: i1, in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i2
  %low_index = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : i2
  %low = llhd.sig.extract %s from %low_index : <i2> -> <i1>
  llhd.drv %low, %a after %time : i1
  %value = llhd.prb %s : i2
  %old_low = comb.extract %value from 0 : (i2) -> i1
  %next = comb.concat %b, %old_low : i1, i1
  %reg = seq.firreg %next clock %clk reset async %rst, %zero : i2
  llhd.drv %s, %reg after %time : i2
  hw.output
}

// -----

// Register state that is observed independently of the signal cannot be dropped.
hw.module @observed_lane(in %clk: !seq.clock, in %a: i1, in %b: i1, out q: i2) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i2
  %low_index = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : i2
  %low = llhd.sig.extract %s from %low_index : <i2> -> <i1>
  llhd.drv %low, %a after %time : i1
  %value = llhd.prb %s : i2
  %old_low = comb.extract %value from 0 : (i2) -> i1
  %next = comb.concat %b, %old_low : i1, i1
  %reg = seq.firreg %next clock %clk : i2
  llhd.drv %s, %reg after %time : i2
  hw.output %reg : i2
}

// -----

// An array element changed in either mux arm is an actual overlapping write.
hw.module @changed_array_element(in %clk: !seq.clock, in %sel: i1, in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.aggregate_constant [false, false] : !hw.array<2xi1>
  %false = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : !hw.array<2xi1>
  %low = llhd.sig.array_get %s[%false] : !llhd.ref<!hw.array<2xi1>>
  llhd.drv %low, %a after %time : i1
  %value = llhd.prb %s : !hw.array<2xi1>
  %next_other = hw.array_inject %value[%false], %b : !hw.array<2xi1>, i1
  %next = comb.mux bin %sel, %value, %next_other : !hw.array<2xi1>
  %reg = seq.firreg %next clock %clk : !hw.array<2xi1>
  llhd.drv %s, %reg after %time : !hw.array<2xi1>
  hw.output
}

// -----

// An array reset writes the copied-through element too.
hw.module @reset_array_element(in %clk: !seq.clock, in %rst: i1, in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.aggregate_constant [false, false] : !hw.array<2xi1>
  %false = hw.constant false
  %true = hw.constant true
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : !hw.array<2xi1>
  %low = llhd.sig.array_get %s[%false] : !llhd.ref<!hw.array<2xi1>>
  llhd.drv %low, %a after %time : i1
  %value = llhd.prb %s : !hw.array<2xi1>
  %next = hw.array_inject %value[%true], %b : !hw.array<2xi1>, i1
  %reg = seq.firreg %next clock %clk reset async %rst, %zero : !hw.array<2xi1>
  llhd.drv %s, %reg after %time : !hw.array<2xi1>
  hw.output
}

// -----

// An enabled write to the independently driven element is still an overlap.
hw.module @changed_enabled_array(in %clk: !seq.clock, in %en: i1, in %a: i3, in %b: i3) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.aggregate_constant [0 : i3, 0 : i3] : !hw.array<2xi3>
  %false = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : !hw.array<2xi3>
  %low = llhd.sig.array_get %s[%false] : !llhd.ref<!hw.array<2xi3>>
  llhd.drv %low, %a after %time : i3
  %value = llhd.prb %s : !hw.array<2xi3>
  %update = hw.array_inject %value[%false], %b : !hw.array<2xi3>, i1
  %next = comb.mux bin %en, %update, %reg : !hw.array<2xi3>
  %reg = seq.firreg %next clock %clk : !hw.array<2xi3>
  llhd.drv %s, %reg after %time : !hw.array<2xi3>
  hw.output
}

// -----

// The hold mux cannot be discarded when its aggregate value is also observed.
hw.module @observed_enabled_next(in %clk: !seq.clock, in %en: i1, in %a: i3, in %b: i3, out next: !hw.array<2xi3>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.aggregate_constant [0 : i3, 0 : i3] : !hw.array<2xi3>
  %false = hw.constant false
  %true = hw.constant true
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : !hw.array<2xi3>
  %low = llhd.sig.array_get %s[%false] : !llhd.ref<!hw.array<2xi3>>
  llhd.drv %low, %a after %time : i3
  %value = llhd.prb %s : !hw.array<2xi3>
  %update = hw.array_inject %value[%true], %b : !hw.array<2xi3>, i1
  %next = comb.mux bin %en, %update, %reg : !hw.array<2xi3>
  %reg = seq.firreg %next clock %clk : !hw.array<2xi3>
  llhd.drv %s, %reg after %time : !hw.array<2xi3>
  hw.output %next : !hw.array<2xi3>
}
