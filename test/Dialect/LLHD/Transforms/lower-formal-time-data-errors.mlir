// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

hw.module @delta_data(out value: !llhd.time) {
  // expected-error @+1 {{time-valued data cannot contain delta or epsilon components}}
  %value = llhd.constant_time <0ns, 1d, 0e>
  hw.output %value : !llhd.time
}

// -----

hw.module @epsilon_data(out value: !llhd.time) {
  // expected-error @+1 {{time-valued data cannot contain delta or epsilon components}}
  %value = llhd.constant_time <0ns, 0d, 1e>
  hw.output %value : !llhd.time
}

// -----

hw.module @sub_femtosecond_data(out value: !llhd.time) {
  // expected-error @+1 {{time-valued data with units smaller than fs is unsupported}}
  %value = llhd.constant_time <1as, 0d, 0e>
  hw.output %value : !llhd.time
}

// -----

hw.module @overflow_data(out value: !llhd.time) {
  // expected-error @+1 {{time-valued data does not fit into i64 femtoseconds}}
  %value = llhd.constant_time <18446744073710ns, 0d, 0e>
  hw.output %value : !llhd.time
}

// -----

hw.module @simulation_time(out value: !llhd.time) {
  // expected-error @+1 {{simulation time queries are unsupported in synchronous formal lowering}}
  %value = llhd.current_time
  hw.output %value : !llhd.time
}

// -----

hw.module @dynamic_wait(in %delay: !llhd.time) {
  llhd.process {
    // expected-error @+1 {{dynamic time delays are unsupported in synchronous formal lowering}}
    llhd.wait delay %delay, ^next
  ^next:
    llhd.halt
  }
  hw.output
}

// -----

// Time-valued data support must not weaken the preflight scheduling check.
hw.module @real_delay(in %value: i1, out stored: i1) {
  %false = hw.constant false
  %delay = llhd.constant_time <1ns, 0d, 0e>
  %sig = llhd.sig %false : i1
  // expected-error @+1 {{real time delays are unsupported in synchronous formal lowering}}
  llhd.drv %sig, %value after %delay : i1
  %stored = llhd.prb %sig : i1
  hw.output %stored : i1
}
