// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf.

// Formal matching evaluates comparisons and updates at the actual counter width.
// CHECK-LABEL: hw.module @countdown
// CHECK: [[N:%.+]] = hw.constant 4 : i8
// CHECK: [[Y:%.+]] = comb.add %x, [[N]] : i8
// CHECK-NEXT: hw.output [[Y]] : i8
hw.module @countdown(in %x: i8, out y: i8) {
  %initial = hw.constant 4 : i8
  %bound = hw.constant 0 : i8
  %step = hw.constant -1 : i8
  %one = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial, %x : i8, i8)
  ^header(%i: i8, %value: i8):
    %continue = comb.icmp ne %i, %bound : i8
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_value = comb.add %value, %one : i8
    %next_i = comb.add %i, %step : i8
    cf.br ^header(%next_i, %next_value : i8, i8)
  ^exit:
    llhd.yield %value : i8
  }
  hw.output %y : i8
}

// CHECK-LABEL: hw.module @posttest
// CHECK: [[N:%.+]] = hw.constant 4 : i8
// CHECK: [[Y:%.+]] = comb.add %x, [[N]] : i8
// CHECK-NEXT: hw.output [[Y]] : i8
hw.module @posttest(in %x: i8, out y: i8) {
  %initial = hw.constant 0 : i8
  %bound = hw.constant 4 : i8
  %step = hw.constant 1 : i8
  %one = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial, %x : i8, i8)
  ^header(%i: i8, %value: i8):
    %next_value = comb.add %value, %one : i8
    %next_i = comb.add %i, %step : i8
    %continue = comb.icmp ult %next_i, %bound : i8
    cf.cond_br %continue, ^header(%next_i, %next_value : i8, i8), ^exit
  ^exit:
    llhd.yield %next_value : i8
  }
  hw.output %y : i8
}

// CHECK-LABEL: hw.module @posttest_once
// CHECK: [[N:%.+]] = hw.constant 1 : i8
// CHECK: [[Y:%.+]] = comb.add %x, [[N]] : i8
// CHECK-NEXT: hw.output [[Y]] : i8
hw.module @posttest_once(in %x: i8, out y: i8) {
  %initial = hw.constant 0 : i8
  %bound = hw.constant 0 : i8
  %step = hw.constant 1 : i8
  %one = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial, %x : i8, i8)
  ^header(%i: i8, %value: i8):
    %next_value = comb.add %value, %one : i8
    %next_i = comb.add %i, %step : i8
    %continue = comb.icmp ult %next_i, %bound : i8
    cf.cond_br %continue, ^header(%next_i, %next_value : i8, i8), ^exit
  ^exit:
    llhd.yield %next_value : i8
  }
  hw.output %y : i8
}

// CHECK-LABEL: hw.module @nonlinear
// CHECK: [[N:%.+]] = hw.constant 3 : i8
// CHECK: [[Y:%.+]] = comb.add %x, [[N]] : i8
// CHECK-NEXT: hw.output [[Y]] : i8
hw.module @nonlinear(in %x: i8, out y: i8) {
  %initial = hw.constant 1 : i8
  %bound = hw.constant 8 : i8
  %step = hw.constant 2 : i8
  %one = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial, %x : i8, i8)
  ^header(%i: i8, %value: i8):
    %continue = comb.icmp ult %i, %bound : i8
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_value = comb.add %value, %one : i8
    %next_i = comb.mul %i, %step : i8
    cf.br ^header(%next_i, %next_value : i8, i8)
  ^exit:
    llhd.yield %value : i8
  }
  hw.output %y : i8
}

// Wrapping is legal when the actual finite-width recurrence reaches its exit.
// CHECK-LABEL: hw.module @finite_wrapping
// CHECK: [[N:%.+]] = hw.constant 3 : i8
// CHECK: [[Y:%.+]] = comb.add %x, [[N]] : i8
// CHECK-NEXT: hw.output [[Y]] : i8
hw.module @finite_wrapping(in %x: i8, out y: i8) {
  %initial = hw.constant 6 : i3
  %bound = hw.constant 1 : i3
  %step = hw.constant 1 : i3
  %one = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%initial, %x : i3, i8)
  ^header(%i: i3, %value: i8):
    %continue = comb.icmp ne %i, %bound : i3
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_value = comb.add %value, %one : i8
    %next_i = comb.add %i, %step : i3
    cf.br ^header(%next_i, %next_value : i3, i8)
  ^exit:
    llhd.yield %value : i8
  }
  hw.output %y : i8
}

// Both counter recurrences participate in the continuation condition.
// CHECK-LABEL: hw.module @two_counters
// CHECK: [[N:%.+]] = hw.constant 2 : i8
// CHECK: [[Y:%.+]] = comb.add %x, [[N]] : i8
// CHECK-NEXT: hw.output [[Y]] : i8
hw.module @two_counters(in %x: i8, out y: i8) {
  %zero = hw.constant 0 : i4
  %one = hw.constant 1 : i4
  %minus_one = hw.constant -1 : i4
  %four = hw.constant 4 : i4
  %increment = hw.constant 1 : i8
  %y = llhd.combinational -> i8 {
    cf.br ^header(%zero, %four, %x : i4, i4, i8)
  ^header(%i: i4, %j: i4, %value: i8):
    %continue = comb.icmp ult %i, %j : i4
    cf.cond_br %continue, ^body, ^exit
  ^body:
    %next_value = comb.add %value, %increment : i8
    %next_i = comb.add %i, %one : i4
    %next_j = comb.add %j, %minus_one : i4
    cf.br ^header(%next_i, %next_j, %next_value : i4, i4, i8)
  ^exit:
    llhd.yield %value : i8
  }
  hw.output %y : i8
}
