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

// An early exit may use both the induction variable and an operation result
// outside the natural loop. The shared exit must receive the values from the
// iteration that exited, including when the loop instead reaches its bound.
// CHECK-LABEL: hw.module @early_exit
// CHECK-DAG: [[TRUE:%.+]] = hw.constant true
// CHECK-DAG: [[FALSE:%.+]] = hw.constant false
// CHECK-DAG: [[ONE:%.+]] = hw.constant 1 : i7
// CHECK-DAG: [[TWO:%.+]] = hw.constant 2 : i8
// CHECK: [[LOW:%.+]] = comb.extract %x from 0 : (i8) -> i7
// CHECK: [[NEXT:%.+]] = comb.add [[LOW]], [[ONE]] : i7
// CHECK: [[FINAL:%.+]] = comb.add %x, [[TWO]] : i8
// CHECK: [[DOUBLED:%.+]] = comb.concat [[NEXT]], [[FALSE]] : i7, i1
// CHECK: [[RESULT:%.+]] = comb.mux %stop, [[DOUBLED]], [[FINAL]] : i8
// CHECK: [[CONTINUE:%.+]] = comb.xor %stop, [[TRUE]] : i1
// CHECK: [[ITERATION:%.+]] = comb.concat [[CONTINUE]], [[FALSE]] : i1, i1
// CHECK-NEXT: hw.output [[RESULT]], [[ITERATION]] : i8, i2
// SIM-LABEL: hw.module @early_exit
// SIM: llhd.combinational
// SIM: comb.icmp ult
// SIM: cf.cond_br
hw.module @early_exit(in %stop: i1, in %x: i8, out y: i8, out iteration: i2) {
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %bound = hw.constant 2 : i2
  %increment = hw.constant 1 : i8
  %y, %iteration = llhd.combinational -> i8, i2 {
    cf.br ^header(%zero, %x : i2, i8)
  ^header(%i: i2, %value: i8):
    %continue = comb.icmp ult %i, %bound : i2
    cf.cond_br %continue, ^body, ^exit(%value : i8)
  ^body:
    %next_value = comb.add %value, %increment : i8
    cf.cond_br %stop, ^break, ^latch
  ^break:
    %doubled = comb.add %next_value, %next_value : i8
    cf.br ^exit(%doubled : i8)
  ^latch:
    %next_i = comb.add %i, %one : i2
    cf.br ^header(%next_i, %next_value : i2, i8)
  ^exit(%result: i8):
    llhd.yield %result, %i : i8, i2
  }
  hw.output %y, %iteration : i8, i2
}

// A zero-trip loop must skip early-exit effects as well as its normal body.
// CHECK-LABEL: hw.module @zero_trip_early_exit
// CHECK-NEXT: hw.output %x : i8
// SIM-LABEL: hw.module @zero_trip_early_exit
// SIM: comb.icmp ult
hw.module @zero_trip_early_exit(in %stop: i1, in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i2
  %one = hw.constant 1 : i2
  %increment = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero, %x : i2, i8)
  ^header(%i: i2, %value: i8):
    %continue = comb.icmp ult %i, %zero : i2
    cf.cond_br %continue, ^body, ^exit
  ^body:
    cf.cond_br %stop, ^break, ^latch
  ^break:
    %break_result = comb.add %value, %increment : i8
    cf.br ^done(%break_result : i8)
  ^latch:
    %next_i = comb.add %i, %one : i2
    cf.br ^header(%next_i, %value : i2, i8)
  ^exit:
    cf.br ^done(%value : i8)
  ^done(%result: i8):
    llhd.yield %result : i8
  }
  hw.output %y : i8
}
