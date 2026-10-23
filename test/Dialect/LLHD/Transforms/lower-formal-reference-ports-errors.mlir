// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

// Writes through an exported reference cannot be replaced with value ports.
hw.module @source(in %d: i1, out q: !llhd.ref<i1>) {
  %false = hw.constant false
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = llhd.sig %false {llhd.unconstrained} : i1
  llhd.drv %q, %d after %time : i1
  hw.output %q : !llhd.ref<i1>
}
hw.module @write_output(in %d: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = hw.instance "source" @source(d: %d: i1) -> (q: !llhd.ref<i1>)
  // expected-error @+1 {{reference ports may only be read or forwarded in formal lowering}}
  llhd.drv %q, %d after %time : i1
  hw.output
}

// -----

// The same ownership rule applies to reference inputs.
hw.module @write_input(in %q: !llhd.ref<i1>, in %d: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  // expected-error @+1 {{reference ports may only be read or forwarded in formal lowering}}
  llhd.drv %q, %d after %time : i1
  hw.output
}

// -----

// Exporting an undriven signal must not turn its placeholder into known data.
hw.module @undriven(out q: !llhd.ref<i1>) {
  %false = hw.constant false
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %q = llhd.sig %false {llhd.unconstrained} : i1
  hw.output %q : !llhd.ref<i1>
}
hw.module @read_undriven(out y: i1) {
  %q = hw.instance "undriven" @undriven() -> (q: !llhd.ref<i1>)
  %y = llhd.prb %q : i1
  hw.output %y : i1
}

// -----

// An external module's reference cannot be converted without its definition.
// expected-error @+1 {{unsupported type remains in formal hardware}}
hw.module.extern @external(out q: !llhd.ref<i1>)
hw.module @read_external(out y: i1) {
  %q = hw.instance "external" @external() -> (q: !llhd.ref<i1>)
  %y = llhd.prb %q : i1
  hw.output %y : i1
}

// -----

// Forwarding references must not hide a combinational dependency cycle.
hw.module @relay(in %q: !llhd.ref<i1>, out value: !llhd.ref<i1>) {
  hw.output %q : !llhd.ref<i1>
}
hw.module @cycle(out y: i1) {
  // expected-error @+1 {{combinational dependency cycle in formal hardware}}
  %q = hw.instance "relay" @relay(q: %q: !llhd.ref<i1>) -> (value: !llhd.ref<i1>)
  %y = llhd.prb %q : i1
  hw.output %y : i1
}
