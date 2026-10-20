// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

// Different updates of the same field still conflict.
hw.module @struct_overlap(in %a: i1, in %b: i1, out q: !hw.struct<a: i1, b: i1>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [false, false] : !hw.struct<a: i1, b: i1>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : !hw.struct<a: i1, b: i1>
  %old = llhd.prb %s : !hw.struct<a: i1, b: i1>
  %first = hw.struct_inject %old["a"], %a : !hw.struct<a: i1, b: i1>
  %second = hw.struct_inject %old["a"], %b : !hw.struct<a: i1, b: i1>
  %other = hw.struct_inject %old["b"], %b : !hw.struct<a: i1, b: i1>
  llhd.drv %s, %first after %time : !hw.struct<a: i1, b: i1>
  llhd.drv %s, %second after %time : !hw.struct<a: i1, b: i1>
  llhd.drv %s, %other after %time : !hw.struct<a: i1, b: i1>
  hw.output %old : !hw.struct<a: i1, b: i1>
}

// -----

// Padding recovery must not hide actual overlapping packed writes.
hw.module @packed_overlap(in %a: i1, in %b: i1, in %high_value: i1, out q: i2) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.constant 0 : i2
  %one = hw.constant true
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : i2
  %old = llhd.prb %s : i2
  %high = comb.extract %old from 1 : (i2) -> i1
  %first = comb.concat %high, %a : i1, i1
  %second = comb.concat %high, %b : i1, i1
  llhd.drv %s, %first after %time : i2
  llhd.drv %s, %second after %time : i2
  %high_ref = llhd.sig.extract %s from %one : <i2> -> <i1>
  llhd.drv %high_ref, %high_value after %time : i1
  hw.output %old : i2
}

// -----

// A copied bit moved to a different position is an actual write.
hw.module @moved_bit(in %a: i1, in %b: i1, out q: i2) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.constant 0 : i2
  %zero = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : i2
  %old = llhd.prb %s : i2
  %high = comb.extract %old from 1 : (i2) -> i1
  %next = comb.concat %a, %high : i1, i1
  llhd.drv %s, %next after %time : i2
  %low_ref = llhd.sig.extract %s from %zero : <i2> -> <i1>
  llhd.drv %low_ref, %b after %time : i1
  hw.output %old : i2
}

// -----

// Reading another signal is an assignment of the other fields, too.
hw.module @other_struct(in %base: !hw.struct<a: i1, b: i1>, in %a: i1, in %b: i1, out q: !hw.struct<a: i1, b: i1>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [false, false] : !hw.struct<a: i1, b: i1>
  %other = llhd.sig %init : !hw.struct<a: i1, b: i1>
  llhd.drv %other, %base after %time : !hw.struct<a: i1, b: i1>
  %old = llhd.prb %other : !hw.struct<a: i1, b: i1>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : !hw.struct<a: i1, b: i1>
  %first = hw.struct_inject %old["a"], %a : !hw.struct<a: i1, b: i1>
  %second = hw.struct_inject %old["b"], %b : !hw.struct<a: i1, b: i1>
  llhd.drv %s, %first after %time : !hw.struct<a: i1, b: i1>
  llhd.drv %s, %second after %time : !hw.struct<a: i1, b: i1>
  %q = llhd.prb %s : !hw.struct<a: i1, b: i1>
  hw.output %q : !hw.struct<a: i1, b: i1>
}

// -----

// Recovering a field target must retain its original scheduling delay.
hw.module @delayed_struct(in %a: i1, in %b: i1, out q: !hw.struct<a: i1, b: i1>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %late = llhd.constant_time <1ns, 0d, 0e>
  %init = hw.aggregate_constant [false, false] : !hw.struct<a: i1, b: i1>
  %s = llhd.sig %init {llhd.unconstrained} : !hw.struct<a: i1, b: i1>
  %old = llhd.prb %s : !hw.struct<a: i1, b: i1>
  %first = hw.struct_inject %old["a"], %a : !hw.struct<a: i1, b: i1>
  %second = hw.struct_inject %old["b"], %b : !hw.struct<a: i1, b: i1>
  // expected-error @+1 {{real time delays are unsupported}}
  llhd.drv %s, %first after %late : !hw.struct<a: i1, b: i1>
  llhd.drv %s, %second after %time : !hw.struct<a: i1, b: i1>
  hw.output %old : !hw.struct<a: i1, b: i1>
}

// -----

// Removing unchanged fields cannot replace undriven storage with its initializer.
hw.module @undriven_field(in %a: i1, out q: !hw.struct<a: i1, b: i1>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [false, false] : !hw.struct<a: i1, b: i1>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : !hw.struct<a: i1, b: i1>
  %old = llhd.prb %s : !hw.struct<a: i1, b: i1>
  %next = hw.struct_inject %old["a"], %a : !hw.struct<a: i1, b: i1>
  llhd.drv %s, %next after %time : !hw.struct<a: i1, b: i1>
  hw.output %old : !hw.struct<a: i1, b: i1>
}
