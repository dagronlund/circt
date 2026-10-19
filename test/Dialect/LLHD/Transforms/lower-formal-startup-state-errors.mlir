// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

// Two startup writers have no defined execution order. Do not pick an order.
hw.module @startup_race(in %clk: !seq.clock, in %data: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %one = hw.constant 1 : i8
  %two = hw.constant 2 : i8
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %one {llhd.explicit_init} : i8
  %old = llhd.prb %s : i8
  %first = llhd.process -> i8 {
    %next = comb.xor %old, %one : i8
    llhd.halt %next : i8
  }
  %second = llhd.process -> i8 {
    %next = comb.xor %old, %two : i8
    llhd.halt %next : i8
  }
  llhd.drv %s, %first after %time : i8
  llhd.drv %s, %second after %time : i8
  %reg = seq.firreg %data clock %clk preset 1 : i8
  llhd.drv %s, %reg after %time : i8
  hw.output
}

// -----

// An unconstrained scheduling value is not a declaration initializer.
hw.module @unconstrained_startup(in %clk: !seq.clock, in %data: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %one = hw.constant 1 : i8
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %one {llhd.unconstrained} : i8
  %old = llhd.prb %s : i8
  %startup = llhd.process -> i8 {
    %next = comb.xor %old, %one : i8
    llhd.halt %next : i8
  }
  llhd.drv %s, %startup after %time : i8
  %reg = seq.firreg %data clock %clk : i8
  llhd.drv %s, %reg after %time : i8
  hw.output
}

// -----

// A nonblocking startup drive is not a blocking initialization update.
hw.module @nonblocking_startup(in %clk: !seq.clock, in %data: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %nba = llhd.constant_time <0ns, 1d, 0e>
  %one = hw.constant 1 : i8
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %one {llhd.explicit_init} : i8
  %old = llhd.prb %s : i8
  %startup = llhd.process -> i8 {
    %next = comb.xor %old, %one : i8
    llhd.halt %next : i8
  }
  llhd.drv %s, %startup after %nba : i8
  %reg = seq.firreg %data clock %clk preset 1 : i8
  llhd.drv %s, %reg after %time : i8
  hw.output
}

// -----

// A startup result consumed by a recurring driver is not an initialization
// drive. Folding it must not erase the recurring assignment to the signal.
hw.module @recurring_startup_result(in %clk: !seq.clock, in %data: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %one = hw.constant 1 : i8
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %one {llhd.explicit_init} : i8
  %old = llhd.prb %s : i8
  %startup = llhd.process -> i8 {
    %next = comb.xor %old, %one : i8
    llhd.halt %next : i8
  }
  llhd.combinational {
    llhd.drv %s, %startup after %time : i8
    llhd.yield
  }
  %reg = seq.firreg %data clock %clk preset 1 : i8
  llhd.drv %s, %reg after %time : i8
  hw.output
}

// -----

// A constant module-level drive without startup provenance is still a driver.
hw.module @unmarked_constant(in %clk: !seq.clock, in %data: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %one = hw.constant 1 : i8
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %one {llhd.unconstrained} : i8
  llhd.drv %s, %one after %time : i8
  %reg = seq.firreg %data clock %clk : i8
  llhd.drv %s, %reg after %time : i8
  hw.output
}

// -----

// Two marked startup writers must not be absorbed in an arbitrary order.
hw.module @marked_startup_race(in %clk: !seq.clock, in %data: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %one = hw.constant 1 : i8
  %two = hw.constant 2 : i8
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %one {llhd.unconstrained} : i8
  llhd.drv %s, %one after %time {llhd.initial} : i8
  llhd.drv %s, %two after %time {llhd.initial} : i8
  %reg = seq.firreg %data clock %clk : i8
  llhd.drv %s, %reg after %time : i8
  hw.output
}

// -----

// Another signal's startup value cannot be read in an assumed process order.
hw.module @other_state(in %clk: !seq.clock, in %data: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %one = hw.constant 1 : i8
  %other = llhd.sig %one {llhd.explicit_init} : i8
  llhd.drv %other, %data after %time : i8
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %one {llhd.explicit_init} : i8
  %old = llhd.prb %s : i8
  %other_value = llhd.prb %other : i8
  %startup = llhd.process -> i8 {
    %next = comb.xor %old, %other_value : i8
    llhd.halt %next : i8
  }
  llhd.drv %s, %startup after %time : i8
  %reg = seq.firreg %data clock %clk preset 1 : i8
  llhd.drv %s, %reg after %time : i8
  hw.output
}
