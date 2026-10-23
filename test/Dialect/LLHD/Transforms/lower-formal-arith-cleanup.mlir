// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith.

// Region simplification creates arith.select, whose canonicalization can
// produce arith.extui rather than leaving a select for formal normalization.
// CHECK-LABEL: hw.module @boolean_to_integer
// CHECK: [[ZERO:%.+]] = hw.constant 0 : i31
// CHECK: [[RESULT:%.+]] = comb.concat [[ZERO]], %enable : i31, i1
// CHECK-NEXT: hw.output [[RESULT]] : i32
hw.module @boolean_to_integer(in %enable: i1, out y: i32) {
  %zero = hw.constant 0 : i32
  %one = hw.constant 1 : i32
  %y = llhd.combinational -> i32 {
    cf.cond_br %enable, ^then, ^else
  ^then:
    cf.br ^exit(%one : i32)
  ^else:
    cf.br ^exit(%zero : i32)
  ^exit(%result: i32):
    llhd.yield %result : i32
  }
  hw.output %y : i32
}

// Swapping the constants materializes arith.xori as well as arith.extui.
// CHECK-LABEL: hw.module @inverted_boolean_to_integer
// CHECK-DAG: [[ZERO:%.+]] = hw.constant 0 : i31
// CHECK-DAG: [[TRUE:%.+]] = hw.constant true
// CHECK: [[NOT:%.+]] = comb.xor %enable, [[TRUE]] : i1
// CHECK: [[RESULT:%.+]] = comb.concat [[ZERO]], [[NOT]] : i31, i1
// CHECK-NEXT: hw.output [[RESULT]] : i32
hw.module @inverted_boolean_to_integer(in %enable: i1, out y: i32) {
  %zero = hw.constant 0 : i32
  %one = hw.constant 1 : i32
  %y = llhd.combinational -> i32 {
    cf.cond_br %enable, ^then, ^else
  ^then:
    cf.br ^exit(%zero : i32)
  ^else:
    cf.br ^exit(%one : i32)
  ^exit(%result: i32):
    llhd.yield %result : i32
  }
  hw.output %y : i32
}

// The same inversion must lower when no integer extension is necessary.
// CHECK-LABEL: hw.module @inverted_boolean
// CHECK: [[TRUE:%.+]] = hw.constant true
// CHECK: [[RESULT:%.+]] = comb.xor %enable, [[TRUE]] : i1
// CHECK-NEXT: hw.output [[RESULT]] : i1
hw.module @inverted_boolean(in %enable: i1, out y: i1) {
  %false = hw.constant false
  %true = hw.constant true
  %y = llhd.combinational -> i1 {
    cf.cond_br %enable, ^then, ^else
  ^then:
    cf.br ^exit(%false : i1)
  ^else:
    cf.br ^exit(%true : i1)
  ^exit(%result: i1):
    llhd.yield %result : i1
  }
  hw.output %y : i1
}
