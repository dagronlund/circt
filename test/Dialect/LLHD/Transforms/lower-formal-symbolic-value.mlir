// RUN: circt-opt %s --lower-llhd-formal-to-core --canonicalize --cse | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf.
// RUN: circt-opt %s --lower-llhd-formal-to-core --lower-llhd-formal-to-core --canonicalize --cse | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf.

// Existing symbolic inputs remain independent under cleanup and are legal
// both before and after strict formal lowering.
// CHECK-LABEL: hw.module @symbolic(
// CHECK: [[A:%.+]] = verif.symbolic_value : i32
// CHECK: [[B:%.+]] = verif.symbolic_value : i32
// CHECK-NEXT: hw.output [[A]], [[A]], [[B]] : i32, i32, i32
hw.module @symbolic(out a: i32, out copy: i32, out b: i32) {
  %a = verif.symbolic_value : i32
  %b = verif.symbolic_value : i32
  hw.output %a, %a, %b : i32, i32, i32
}

// A module-level symbolic predicate survives combinational process lowering.
// Its assumption retains the original branch guard.
// CHECK-LABEL: hw.module @conditional(
// CHECK: [[PRED:%.+]] = verif.symbolic_value : i1
// CHECK: verif.assume [[PRED]] if %enable : i1
// CHECK: hw.output [[PRED]] : i1
hw.module @conditional(in %enable: i1, out predicate: i1) {
  %predicate = verif.symbolic_value : i1
  llhd.combinational {
    cf.cond_br %enable, ^check, ^exit
  ^check:
    verif.assume %predicate : i1
    cf.br ^exit
  ^exit:
    llhd.yield
  }
  hw.output %predicate : i1
}

// Symbolic data feeds enabled registers without changing the sampling edge or
// holding behavior. Checks using the source retain their edge and enable too.
// CHECK-LABEL: hw.module @positive(
// CHECK: [[SOURCE:%.+]] = verif.symbolic_value : i32
// CHECK: [[PRED:%.+]] = comb.icmp {{(bin )?}}ule [[SOURCE]], %limit : i32
// CHECK: verif.clocked_assume [[PRED]] if %enable, posedge %clk : i1
// CHECK-DAG: [[NEXT:%.+]] = comb.mux bin %enable, [[SOURCE]], [[Q:%.+]] : i32
// CHECK-DAG: [[Q]] = seq.firreg [[NEXT]] clock {{%.+}} : i32
// CHECK: hw.output [[Q]] : i32
hw.module @positive(in %clk: i1, in %enable: i1, in %limit: i32, out q: i32) {
  %source = verif.symbolic_value : i32
  %true = hw.constant true
  %zero = hw.constant 0 : i32
  %time = llhd.constant_time <0ns, 1d, 0e>
  %storage = llhd.sig %zero {llhd.unconstrained} : i32
  %q = llhd.prb %storage : i32
  llhd.process {
    cf.br ^wait
  ^wait:
    llhd.wait (%clk : i1), ^edge(%clk : i1)
  ^edge(%oldclk: i1):
    %notold = comb.xor %oldclk, %true : i1
    %rise = comb.and %notold, %clk : i1
    cf.cond_br %rise, ^body, ^wait
  ^body:
    cf.cond_br %enable, ^sample, ^wait
  ^sample:
    %predicate = comb.icmp ule %source, %limit : i32
    verif.assume %predicate : i1
    llhd.drv %storage, %source after %time : i32
    cf.br ^wait
  }
  hw.output %q : i32
}

// CHECK-LABEL: hw.module @negative(
// CHECK: [[SOURCE:%.+]] = verif.symbolic_value : i32
// CHECK: [[PRED:%.+]] = comb.icmp {{(bin )?}}ule [[SOURCE]], %limit : i32
// CHECK: verif.clocked_assume [[PRED]] if %enable, negedge %clk : i1
// CHECK: seq.clock_inv
// CHECK-DAG: [[NEXT:%.+]] = comb.mux bin %enable, [[SOURCE]], [[Q:%.+]] : i32
// CHECK-DAG: [[Q]] = seq.firreg [[NEXT]] clock {{%.+}} : i32
// CHECK: hw.output [[Q]] : i32
hw.module @negative(in %clk: i1, in %enable: i1, in %limit: i32, out q: i32) {
  %source = verif.symbolic_value : i32
  %true = hw.constant true
  %zero = hw.constant 0 : i32
  %time = llhd.constant_time <0ns, 1d, 0e>
  %storage = llhd.sig %zero {llhd.unconstrained} : i32
  %q = llhd.prb %storage : i32
  llhd.process {
    cf.br ^wait
  ^wait:
    llhd.wait (%clk : i1), ^edge(%clk : i1)
  ^edge(%oldclk: i1):
    %notclk = comb.xor %clk, %true : i1
    %fall = comb.and %oldclk, %notclk : i1
    cf.cond_br %fall, ^body, ^wait
  ^body:
    cf.cond_br %enable, ^sample, ^wait
  ^sample:
    %predicate = comb.icmp ule %source, %limit : i32
    verif.assume %predicate : i1
    llhd.drv %storage, %source after %time : i32
    cf.br ^wait
  }
  hw.output %q : i32
}
