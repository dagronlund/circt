// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf.
// RUN: circt-opt %s --llhd-unroll-loops | FileCheck %s --check-prefix=SIM

// Formal normalization recognizes a zero-extended counter without changing
// the ordinary loop-unrolling pass's matching rules.
// CHECK-LABEL: hw.module @extended_counter
// CHECK: [[TWO:%.+]] = hw.constant 2 : i8
// CHECK: [[RESULT:%.+]] = comb.add %x, [[TWO]] : i8
// CHECK-NEXT: hw.output [[RESULT]] : i8
// SIM-LABEL: hw.module @extended_counter
// SIM: llhd.combinational
// SIM: comb.icmp ult
// SIM: cf.cond_br
hw.module @extended_counter(in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %high = hw.constant 0 : i30
  %bound = hw.constant 2 : i32
  %increment = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero, %x : i2, i8)
  ^header(%i: i2, %value: i8):
    %wide = comb.concat %high, %i : i30, i2
    %continue = comb.icmp ult %wide, %bound : i32
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_value = comb.add %value, %increment : i8
    %next_i = comb.add %i, %one : i2
    cf.br ^header(%next_i, %next_value : i2, i8)
  ^exit:
    llhd.yield %value : i8
  }
  hw.output %y : i8
}
