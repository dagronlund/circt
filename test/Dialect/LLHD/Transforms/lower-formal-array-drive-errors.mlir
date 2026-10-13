// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

// Recovering partial assignments must still reject overlapping element drives.
hw.module @overlap(in %a: i4, in %b: i4, in %sel: i1, out q: i4) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant false
  %init = hw.aggregate_constant [0 : i4, 0 : i4] : !hw.array<2xi4>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi4>
  %old = llhd.prb %data : !hw.array<2xi4>
  %first = hw.array_inject %old[%zero], %a : !hw.array<2xi4>, i1
  %second = hw.array_inject %old[%zero], %b : !hw.array<2xi4>, i1
  llhd.drv %data, %first after %time : !hw.array<2xi4>
  llhd.drv %data, %second after %time : !hw.array<2xi4>
  %q = hw.array_get %old[%sel] : !hw.array<2xi4>, i1
  hw.output %q : i4
}

// -----

// A dynamic write may overlap the static assignment.
hw.module @dynamic_write(in %a: i4, in %b: i4, in %sel: i1, out q: i4) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant false
  %init = hw.aggregate_constant [0 : i4, 0 : i4] : !hw.array<2xi4>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi4>
  %old = llhd.prb %data : !hw.array<2xi4>
  %first = hw.array_inject %old[%zero], %a : !hw.array<2xi4>, i1
  %second = hw.array_inject %old[%sel], %b : !hw.array<2xi4>, i1
  llhd.drv %data, %first after %time : !hw.array<2xi4>
  llhd.drv %data, %second after %time : !hw.array<2xi4>
  %q = hw.array_get %old[%sel] : !hw.array<2xi4>, i1
  hw.output %q : i4
}

// -----

// Probing a different signal really drives the other elements too.
hw.module @other_base(in %a: i4, in %b: i4, in %base: !hw.array<2xi4>, out q: !hw.array<2xi4>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant false
  %one = hw.constant true
  %init = hw.aggregate_constant [0 : i4, 0 : i4] : !hw.array<2xi4>
  %other = llhd.sig %init : !hw.array<2xi4>
  llhd.drv %other, %base after %time : !hw.array<2xi4>
  %old = llhd.prb %other : !hw.array<2xi4>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi4>
  %first = hw.array_inject %old[%zero], %a : !hw.array<2xi4>, i1
  %second = hw.array_inject %old[%one], %b : !hw.array<2xi4>, i1
  llhd.drv %data, %first after %time : !hw.array<2xi4>
  llhd.drv %data, %second after %time : !hw.array<2xi4>
  %q = llhd.prb %data : !hw.array<2xi4>
  hw.output %q : !hw.array<2xi4>
}

// -----

// Recovering the target must retain the original scheduling delay.
hw.module @delayed(in %a: i4, in %b: i4, in %sel: i1, out q: i4) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %late = llhd.constant_time <1ns, 0d, 0e>
  %zero = hw.constant false
  %one = hw.constant true
  %init = hw.aggregate_constant [0 : i4, 0 : i4] : !hw.array<2xi4>
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi4>
  %old = llhd.prb %data : !hw.array<2xi4>
  %first = hw.array_inject %old[%zero], %a : !hw.array<2xi4>, i1
  %second = hw.array_inject %old[%one], %b : !hw.array<2xi4>, i1
  // expected-error @+1 {{real time delays are unsupported}}
  llhd.drv %data, %first after %late : !hw.array<2xi4>
  llhd.drv %data, %second after %time : !hw.array<2xi4>
  %q = hw.array_get %old[%sel] : !hw.array<2xi4>, i1
  hw.output %q : i4
}

// -----

// A dynamic read can observe an unwritten element. Do not fill it from the
// scheduling initializer when removing the passthrough portion of a drive.
hw.module @undriven_element(in %a: i4, in %sel: i1, out q: i4) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant false
  %init = hw.aggregate_constant [0 : i4, 0 : i4] : !hw.array<2xi4>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi4>
  %old = llhd.prb %data : !hw.array<2xi4>
  %next = hw.array_inject %old[%zero], %a : !hw.array<2xi4>, i1
  llhd.drv %data, %next after %time : !hw.array<2xi4>
  %q = hw.array_get %old[%sel] : !hw.array<2xi4>, i1
  hw.output %q : i4
}

// -----

// Whole-array registers recovered from partial assignments must still reject
// two actual updates to the same lane.
hw.module @register_overlap(in %clk: !seq.clock, in %a: i4, in %b: i4,
                            out q: !hw.array<2xi4>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant false
  %init = hw.aggregate_constant [0 : i4, 0 : i4] : !hw.array<2xi4>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi4>
  %old = llhd.prb %data : !hw.array<2xi4>
  %first = hw.array_inject %old[%zero], %a : !hw.array<2xi4>, i1
  %second = hw.array_inject %old[%zero], %b : !hw.array<2xi4>, i1
  %first_reg = seq.firreg %first clock %clk : !hw.array<2xi4>
  %second_reg = seq.firreg %second clock %clk : !hw.array<2xi4>
  llhd.drv %data, %first_reg after %time : !hw.array<2xi4>
  llhd.drv %data, %second_reg after %time : !hw.array<2xi4>
  hw.output %old : !hw.array<2xi4>
}

// -----

// An independently observed register owns all its lanes, even if its update
// copies some of them from the driven signal. Do not discard its padding state.
hw.module @observed_register(in %clk: !seq.clock, in %a: i4, in %b: i4,
                             out q: !hw.array<2xi4>, out state: !hw.array<2xi4>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant false
  %one = hw.constant true
  %init = hw.aggregate_constant [0 : i4, 0 : i4] : !hw.array<2xi4>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi4>
  %old = llhd.prb %data : !hw.array<2xi4>
  %first = hw.array_inject %old[%zero], %a : !hw.array<2xi4>, i1
  %second = hw.array_inject %old[%one], %b : !hw.array<2xi4>, i1
  %first_reg = seq.firreg %first clock %clk : !hw.array<2xi4>
  %second_reg = seq.firreg %second clock %clk : !hw.array<2xi4>
  llhd.drv %data, %first_reg after %time : !hw.array<2xi4>
  llhd.drv %data, %second_reg after %time : !hw.array<2xi4>
  hw.output %old, %first_reg : !hw.array<2xi4>, !hw.array<2xi4>
}
