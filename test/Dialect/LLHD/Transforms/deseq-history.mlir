// RUN: circt-opt %s --llhd-deseq --canonicalize | FileCheck %s

// A history operation must see the clock waveform, even when the process is
// specialized under the assumption that a rising edge has occurred.
// CHECK-LABEL: @PastClock(
hw.module @PastClock(in %clock: i1) {
  %false = hw.constant false
  %time = llhd.constant_time <0ns, 1d, 0e>
  // CHECK: [[PAST:%.+]] = ltl.past %clock, 3 clk %clock : i1
  // CHECK-NOT: llhd.process
  // CHECK: [[CLK:%.+]] = seq.to_clock %clock
  // CHECK: seq.firreg [[PAST]] clock [[CLK]]
  %out, %en = llhd.process -> i1, i1 {
    %true = hw.constant true
    cf.br ^bb1(%false, %false : i1, i1)
  ^bb1(%a: i1, %b: i1):
    llhd.wait yield (%a, %b : i1, i1), (%clock : i1), ^bb2(%clock : i1)
  ^bb2(%oldClock: i1):
    %notOldClock = comb.xor bin %oldClock, %true : i1
    %posedge = comb.and bin %notOldClock, %clock : i1
    %past = ltl.past %clock, 3 clk %clock : i1
    cf.cond_br %posedge, ^bb1(%past, %true : i1, i1), ^bb1(%false, %false : i1, i1)
  }
  %sig = llhd.sig %false : i1
  llhd.drv %sig, %out after %time if %en : i1
}

// Do not specialize history that still depends on values inside the process.
// CHECK-LABEL: @PastLocalDependency(
hw.module @PastLocalDependency(in %clock: i1) {
  %false = hw.constant false
  %time = llhd.constant_time <0ns, 1d, 0e>
  // CHECK: llhd.process
  // CHECK: [[INPUT:%.+]] = comb.xor bin %clock, {{%.+}} : i1
  // CHECK: ltl.past [[INPUT]], 3 clk %clock : i1
  // CHECK-NOT: seq.firreg
  %out, %en = llhd.process -> i1, i1 {
    %true = hw.constant true
    cf.br ^bb1(%false, %false : i1, i1)
  ^bb1(%a: i1, %b: i1):
    llhd.wait yield (%a, %b : i1, i1), (%clock : i1), ^bb2(%clock : i1)
  ^bb2(%oldClock: i1):
    %notOldClock = comb.xor bin %oldClock, %true : i1
    %posedge = comb.and bin %notOldClock, %clock : i1
    %input = comb.xor bin %clock, %true : i1
    %past = ltl.past %input, 3 clk %clock : i1
    cf.cond_br %posedge, ^bb1(%past, %true : i1, i1), ^bb1(%false, %false : i1, i1)
  }
  %sig = llhd.sig %false : i1
  llhd.drv %sig, %out after %time if %en : i1
}
