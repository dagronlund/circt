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
