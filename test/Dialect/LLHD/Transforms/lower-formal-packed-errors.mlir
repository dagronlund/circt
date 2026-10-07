// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

// Slicing must retain an actual dependency through a combinational child.
hw.module @packed_cycle(in %ack: i1, out ready: i1, out packed: i2) {
  %false = hw.constant false
  %high = comb.concat %ack, %false : i1, i1
  %low = comb.concat %false, %ready : i1, i1
  %packed = comb.or bin %high, %low : i2
  %next = comb.extract %packed from 0 : (i2) -> i1
  // expected-error @+1 {{combinational dependency cycle}}
  %ready = hw.instance "relay" @cycle_relay(ack: %next: i1) -> (ready: i1)
  hw.output %ready, %packed : i1, i2
}
hw.module @cycle_relay(in %ack: i1, out ready: i1) {
  hw.output %ack : i1
}

// -----

// Overlapping lanes also retain both dependencies after slicing.
hw.module @overlapping_cycle(in %ack: i1, out ready: i1, out packed: i2) {
  %false = hw.constant false
  %high = comb.concat %ack, %false : i1, i1
  %overlap = comb.concat %ready, %false : i1, i1
  %packed = comb.or %high, %overlap : i2
  %next = comb.extract %packed from 1 : (i2) -> i1
  // expected-error @+1 {{combinational dependency cycle}}
  %ready = hw.instance "relay" @overlap_relay(ack: %next: i1) -> (ready: i1)
  hw.output %ready, %packed : i1, i2
}
hw.module @overlap_relay(in %ack: i1, out ready: i1) {
  hw.output %ack : i1
}
