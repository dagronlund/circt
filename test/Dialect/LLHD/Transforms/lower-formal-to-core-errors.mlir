// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

hw.module @side_effect(in %str: !hw.string) {
  // expected-error @+1 {{unsupported verification effect}}
  verif.print %str
  hw.output
}

// -----

hw.module @loop(in %a: i1) {
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  llhd.combinational {
    cf.br ^body
  ^body:
    verif.assert %a : i1
    cf.br ^body
  }
  hw.output
}

// -----

hw.module @unbounded(in %clk: i1, in %a: i1) {
  // expected-error @+1 {{unbounded or variable temporal sequence is unsupported}}
  %p = ltl.delay %a, 1 : i1
  verif.clocked_cover %p, posedge %clk : !ltl.sequence
  hw.output
}

// -----

hw.module @until(in %clk: i1, in %a: i1, in %b: i1) {
  // expected-error @+1 {{unsupported temporal operator}}
  %p = ltl.until %a, %b : i1, i1
  verif.clocked_assume %p, posedge %clk : !ltl.property
  hw.output
}

// -----

hw.module @both(in %clk: i1, in %a: i1) {
  // expected-error @+1 {{both-edge properties are unsupported}}
  verif.clocked_assert %a, edge %clk : i1
  hw.output
}

// -----

hw.module @multidriver(in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %a : i1
  llhd.drv %s, %a after %time : i1
  llhd.drv %s, %b after %time : i1
  hw.output
}

// -----

hw.module @time(in %a: i1) {
  %t = llhd.constant_time <1ns, 0d, 0e>
  %s = llhd.sig %a : i1
  // expected-error @+1 {{real time delays are unsupported}}
  llhd.drv %s, %a after %t : i1
  hw.output
}

// -----

hw.module @cycle(in %a: i1, out y: i1) {
  %x = comb.xor %y, %a : i1
  // expected-error @+1 {{combinational dependency cycle}}
  %y = comb.xor %x, %a : i1
  hw.output %y : i1
}

// -----

hw.module @limit(in %clk: i1, in %a: i1) {
  %p = ltl.delay %a, 257, 0 : i1
  // expected-error @+1 {{temporal monitor exceeds max-monitor-depth}}
  verif.clocked_assert %p, posedge %clk : !ltl.sequence
  hw.output
}

// -----

// expected-error @+1 {{unsupported type remains in formal hardware}}
hw.module @unused_temporal_input(in %p: !ltl.property) {
  hw.output
}

// -----

hw.module @unclocked(in %a: i1) {
  %p = ltl.delay %a, 2, 0 : i1
  // expected-error @+1 {{temporal property has no sampling clock}}
  verif.assert %p : !ltl.sequence
  hw.output
}

// -----

hw.module @multiple_clocks(in %clk: i1, in %other: i1, in %a: i1) {
  %p = ltl.clocked_atom %a, negedge %other : i1
  // expected-error @-1 {{property observes multiple unrelated clocks}}
  verif.clocked_assert %p, posedge %clk : !ltl.sequence
  hw.output
}

// -----

hw.module @immediate_loop(in %a: i1) {
  // expected-error @+1 {{unsupported formal process}}
  llhd.process {
    cf.br ^body
  ^body:
    verif.assert %a : i1
    cf.br ^body
  }
  hw.output
}

// -----

hw.module @before_wait(in %clk: i1, in %a: i1) {
  // expected-error @+1 {{unsupported formal process}}
  llhd.process {
    verif.assert %a : i1
    cf.br ^wait
  ^wait:
    llhd.wait (%clk : i1), ^edge(%clk : i1)
  ^edge(%old: i1):
    cf.br ^wait
  }
  hw.output
}

// -----

hw.module @negative_delay(in %clk: i1, in %a: i1) {
  %p = ltl.delay %a, -1, 0 : i1
  // expected-error @+1 {{temporal monitor exceeds max-monitor-depth}}
  verif.clocked_assert %p, posedge %clk : !ltl.sequence
  hw.output
}
