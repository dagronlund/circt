// RUN: circt-opt %s --verify-diagnostics
hw.module @invalid() {
  sv.initial {
    %fmt = sim.string.literal "%d"
    %n = hw.constant 1 : i32
    // expected-error @+1 {{requires one signedness flag per value}}
    %s = sim.sv.sformat_dynamic %fmt(%n) {isSigned = array<i1>} : i32
  }
  hw.output
}
