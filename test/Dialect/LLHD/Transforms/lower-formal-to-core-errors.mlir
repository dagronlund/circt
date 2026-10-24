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

// The mathematical trip count is two, but the i2 counter wraps from two to
// zero and never exits. Formal normalization must leave this loop unsupported.
hw.module @wrapping_counter(in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i2
  %step = hw.constant 2 : i2
  %high = hw.constant 0 : i30
  %bound = hw.constant 3 : i32
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero : i2)
  ^header(%i: i2):
    %wide = comb.concat %high, %i : i30, i2
    %continue = comb.icmp ult %wide, %bound : i32
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next = comb.add %i, %step : i2
    cf.br ^header(%next : i2)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// A widened comparison against four cannot be narrowed to an i2 counter.
hw.module @unreachable_counter_bound(in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i2
  %step = hw.constant 1 : i2
  %high = hw.constant 0 : i30
  %bound = hw.constant 4 : i32
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero : i2)
  ^header(%i: i2):
    %wide = comb.concat %high, %i : i30, i2
    %continue = comb.icmp ult %wide, %bound : i32
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next = comb.add %i, %step : i2
    cf.br ^header(%next : i2)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// Even a statically bounded loop cannot be expanded across sampling waits.
hw.module @suspending_loop(in %clk: i1) {
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %bound = hw.constant 2 : i2
  // expected-error @+1 {{unsupported formal process}}
  llhd.process {
    cf.br ^header(%zero : i2)
  ^header(%i: i2):
    %continue = comb.icmp ult %i, %bound : i2
    cf.cond_br %continue, ^body, ^exit
  ^body:
    llhd.wait (%clk : i1), ^latch
  ^latch:
    %next = comb.add %i, %one : i2
    cf.br ^header(%next : i2)
  ^exit:
    llhd.halt
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

// Splitting an array must still reject overlapping element drivers.
hw.module @overlapping_array_drivers(in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant false
  %init = hw.aggregate_constant [false, false] : !hw.array<2xi1>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : !hw.array<2xi1>
  %elem = llhd.sig.array_get %s[%zero] : !llhd.ref<!hw.array<2xi1>>
  llhd.drv %elem, %a after %time : i1
  llhd.drv %elem, %b after %time : i1
  hw.output
}

// -----

// An observable undriven signal must not become its scheduling initializer.
hw.module @undriven_output(out y: i4) {
  %zero = hw.constant 0 : i4
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : i4
  %y = llhd.prb %s : i4
  hw.output %y : i4
}

// -----

// Splitting packed storage must still reject an observable undriven slice.
hw.module @undriven_packed_slice(in %a: i4, out y: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i8
  %low = hw.constant 0 : i3
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %zero {llhd.unconstrained} : i8
  %slice = llhd.sig.extract %s from %low : <i8> -> <i4>
  llhd.drv %slice, %a after %time : i4
  %y = llhd.prb %s : i8
  hw.output %y : i8
}

// -----

// Check local storage before Mem2Reg can replace probes with its initializer.
hw.module @local_undriven_output(out y: i4) {
  %zero = hw.constant 0 : i4
  %y = llhd.combinational -> i4 {
    // expected-error @+1 {{signal must have exactly one resolved driver}}
    %s = llhd.sig %zero {llhd.unconstrained} : i4
    %value = llhd.prb %s : i4
    llhd.yield %value : i4
  }
  hw.output %y : i4
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

// -----

// Separate combinational regions remain independent drivers even when their
// control-flow paths are mutually exclusive.
hw.module @combinational_multidriver(in %sel: i1, in %a: i1, in %b: i1) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %a : i1
  llhd.combinational {
    cf.cond_br %sel, ^bb1, ^bb2
  ^bb1:
    llhd.drv %s, %a after %time : i1
    cf.br ^bb2
  ^bb2:
    llhd.yield
  }
  llhd.combinational {
    cf.cond_br %sel, ^bb2, ^bb1
  ^bb1:
    llhd.drv %s, %b after %time : i1
    cf.br ^bb2
  ^bb2:
    llhd.yield
  }
  hw.output
}

// -----

// Best-effort Arith normalization must retain the strict final legality check.
hw.module @unsupported_arithmetic(in %x: i8, in %divisor: i8, out y: i8) {
  // expected-error @+1 {{operation remains after strict formal lowering; unsupported arith.ceildivsi}}
  %y = arith.ceildivsi %x, %divisor : i8
  hw.output %y : i8
}

// -----

// A comparison in a continuation disjunction does not bound the loop: the
// dynamic guard can keep it running after the counter reaches that bound.
hw.module @unbounded_disjunction(in %guard: i1, in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %bound = hw.constant 2 : i2
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero : i2)
  ^header(%i: i2):
    %bounded = comb.icmp ult %i, %bound : i2
    %continue = comb.or %guard, %bounded : i1
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_i = comb.add %i, %one : i2
    cf.br ^header(%next_i : i2)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// Different increments on the back-edges cannot be treated as a fixed trip
// count. In particular, repeatedly taking the +2 edge wraps the i2 counter.
hw.module @path_dependent_increment(in %choose: i1, in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %two = hw.constant 2 : i2
  %bound = hw.constant 3 : i2
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero : i2)
  ^header(%i: i2):
    %continue = comb.icmp ult %i, %bound : i2
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_one = comb.add %i, %one : i2
    %next_two = comb.add %i, %two : i2
    cf.cond_br %choose, ^header(%next_one : i2), ^header(%next_two : i2)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// A back-edge which skips the increment can keep the loop running forever.
hw.module @skipped_increment(in %choose: i1, in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %bound = hw.constant 2 : i2
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero : i2)
  ^header(%i: i2):
    %continue = comb.icmp ult %i, %bound : i2
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_i = comb.add %i, %one : i2
    cf.cond_br %choose, ^header(%next_i : i2), ^header(%i : i2)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// An even counter cannot reach an odd inequality bound.
hw.module @unreachable_inequality(in %x: i8, out y: i8) {
  %initial = hw.constant 0 : i3
  %bound = hw.constant 3 : i3
  %step = hw.constant 2 : i3
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial : i3)
  ^header(%i: i3):
    %continue = comb.icmp ne %i, %bound : i3
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next = comb.add %i, %step : i3
    cf.br ^header(%next : i3)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// Multiplication wraps to zero and then stays there forever.
hw.module @nonlinear_cycle(in %x: i8, out y: i8) {
  %initial = hw.constant 1 : i3
  %bound = hw.constant 7 : i3
  %step = hw.constant 2 : i3
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial : i3)
  ^header(%i: i3):
    %continue = comb.icmp ult %i, %bound : i3
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next = comb.mul %i, %step : i3
    cf.br ^header(%next : i3)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// A latch comparison cannot bound a path which bypasses that latch entirely.
hw.module @bypassed_bound(in %choose: i1, in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i3
  %one = hw.constant 1 : i3
  %bound = hw.constant 4 : i3
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero : i3)
  ^header(%i: i3):
    %next = comb.add %i, %one : i3
    cf.cond_br %choose, ^header(%next : i3), ^latch
  ^latch:
    %continue = comb.icmp ult %next, %bound : i3
    cf.cond_br %continue, ^header(%next : i3), ^exit
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// Division by zero has no concrete counter value.
hw.module @unknown_division_update(in %x: i8, out y: i8) {
  %initial = hw.constant 1 : i32
  %bound = hw.constant 4 : i32
  %zero = hw.constant 0 : i32
  %one = hw.constant 1 : i32
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial : i32)
  ^header(%i: i32):
    %continue = comb.icmp ult %i, %bound : i32
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next = comb.divu %i, %zero : i32
    cf.br ^header(%next : i32)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}

// -----

// A finite recurrence must still obey the unrolling expansion limit.
hw.module @loop_expansion_limit(in %x: i8, out y: i8) {
  %initial = hw.constant 0 : i32
  %bound = hw.constant 1024 : i32
  %zero = hw.constant 0 : i32
  %one = hw.constant 1 : i32
  // expected-error @+1 {{unsupported control-flow cycle or effect}}
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial : i32)
  ^header(%i: i32):
    %continue = comb.icmp ult %i, %bound : i32
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next = comb.add %i, %one : i32
    cf.br ^header(%next : i32)
  ^exit:
    llhd.yield %x : i8
  }
  hw.output %y : i8
}
