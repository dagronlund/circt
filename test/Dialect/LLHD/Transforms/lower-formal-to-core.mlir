// RUN: circt-opt %s --lower-llhd-formal-to-core --canonicalize --cse | FileCheck %s
// RUN: circt-opt %s --lower-llhd-formal-to-core | %PYTHON% %S/Inputs/formal-traces.py
// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --check-prefix=STRICT --implicit-check-not=llhd. --implicit-check-not=ltl. --implicit-check-not=cf. --implicit-check-not=unrealized_conversion_cast
// STRICT: module {

// CHECK-LABEL: @combinational(
// CHECK: verif.assume %a label "unconditional"
// CHECK: verif.assert {{.*}} if {{.*}} label "nested"
// CHECK: verif.assume {{.*}} if {{.*}} label "nested_assume"
// CHECK: verif.cover {{.*}} if {{.*}} label "disabled_cover"
// CHECK: comb.mux
// CHECK: verif.assert {{.*}} label "merge"
hw.module @combinational(in %a: i1, in %b: i1, in %en: i1) {
  llhd.combinational {
    verif.assume %a label "unconditional" : i1
    cf.cond_br %a, ^yes, ^no
  ^yes:
    cf.cond_br %b, ^nested, ^merge(%b : i1)
  ^nested:
    verif.assert %en if %b label "nested" : i1
    verif.assume %en if %b label "nested_assume" : i1
    verif.cover %en if %b label "disabled_cover" : i1
    cf.br ^merge(%a : i1)
  ^no:
    cf.br ^merge(%en : i1)
  ^merge(%v: i1):
    verif.assert %v label "merge" : i1
    llhd.yield
  }
  hw.output
}

// CHECK-LABEL: @procedural(
// CHECK: verif.clocked_assert %qs if %en, posedge %clk label "oldq"
// CHECK: verif.clocked_cover {{.*}} if %en, posedge %clk label "blocking"
// CHECK: verif.clocked_assert %rs if %en, posedge %clk label "oldr"
// CHECK: %qs = seq.firreg {{.*}} preset 0 : i1
// CHECK: %rs = seq.firreg {{.*}} preset 1 : i1
hw.module @procedural(in %clk: i1, in %en: i1, in %d: i1, out q: i1, out r: i1) {
  %false = hw.constant false
  %true = hw.constant true
  %time = llhd.constant_time <0ns, 1d, 0e>
  %qs = llhd.sig %false : i1
  %rs = llhd.sig %true : i1
  %q = llhd.prb %qs : i1
  %r = llhd.prb %rs : i1
  %v, %w, %e = llhd.process -> i1, i1, i1 {
    cf.br ^wait(%false, %false, %false : i1, i1, i1)
  ^wait(%nextq: i1, %nextr: i1, %enable: i1):
    llhd.wait yield (%nextq, %nextr, %enable : i1, i1, i1), (%clk : i1), ^edge(%clk : i1)
  ^edge(%oldclk: i1):
    %notold = comb.xor %oldclk, %true : i1
    %rise = comb.and %notold, %clk : i1
    cf.cond_br %rise, ^body, ^wait(%q, %r, %false : i1, i1, i1)
  ^body:
    cf.cond_br %en, ^checks, ^wait(%q, %r, %false : i1, i1, i1)
  ^checks:
    verif.assert %q label "oldq" : i1
    %local = comb.xor %q, %true : i1
    verif.cover %local label "blocking" : i1
    verif.assert %r label "oldr" : i1
    cf.br ^wait(%d, %q, %true : i1, i1, i1)
  }
  llhd.drv %qs, %v after %time if %e : i1
  llhd.drv %rs, %w after %time if %e : i1
  hw.output %q, %r : i1, i1
}

// CHECK-LABEL: @temporal(
// CHECK: seq.firreg {{.*}} reset async {{.*}} preset 0 : i1
// CHECK: verif.clocked_assert %b if {{.*}}, posedge %clk label "next"
// CHECK: verif.clocked_assume %b if {{.*}}, posedge %clk label "next_assume"
// CHECK: verif.clocked_cover {{.*}}, posedge %clk label "next_cover"
// CHECK: verif.clocked_cover {{.*}}, posedge %clk label "sequence"
// CHECK: verif.clocked_cover {{.*}}, posedge %clk label "repeat"
hw.module @temporal(in %clk: i1, in %a: i1, in %b: i1, in %en: i1) {
  %true = hw.constant true
  %tick = ltl.delay %true, 1, 0 : i1
  %antecedent = ltl.concat %a, %tick : i1, !ltl.sequence
  %next = ltl.implication %antecedent, %b : !ltl.sequence, i1
  verif.clocked_assert %next if %en, posedge %clk label "next" : !ltl.property
  verif.clocked_assume %next if %en, posedge %clk label "next_assume" : !ltl.property
  verif.clocked_cover %next if %en, posedge %clk label "next_cover" : !ltl.property
  %later = ltl.delay %b, 1, 0 : i1
  %sequence = ltl.concat %a, %later : i1, !ltl.sequence
  verif.clocked_cover %sequence if %en, posedge %clk label "sequence" : !ltl.sequence
  verif.clocked_assert %sequence if %en, posedge %clk label "sequence_assert" : !ltl.sequence
  verif.clocked_assume %sequence if %en, posedge %clk label "sequence_assume" : !ltl.sequence
  %twice = ltl.repeat %a, 2, 0 : i1
  %repeat = ltl.concat %twice, %later : !ltl.sequence, !ltl.sequence
  verif.clocked_cover %repeat if %en, posedge %clk label "repeat" : !ltl.sequence
  %same = ltl.implication %a, %b : i1, i1
  verif.clocked_assert %same if %en, posedge %clk label "same" : !ltl.property
}

// CHECK-LABEL: @wrapper(
// CHECK: verif.clocked_assert %a, negedge %clk label "wrapped"
hw.module @wrapper(in %clk: i1, in %a: i1) {
  llhd.process {
    cf.br ^body
  ^body:
    verif.clocked_assert %a, negedge %clk label "wrapped" : i1
    cf.br ^body
  }
  hw.output
}

// CHECK-LABEL: @history(
// CHECK: seq.compreg %a, {{.*}} : i1
// CHECK-NOT: initial
// CHECK: verif.clocked_cover {{.*}}, posedge %clk label "past"
hw.module @history(in %clk: i1, in %a: i1) {
  %past = ltl.past %a, 2 clk %clk : i1
  verif.clocked_cover %past, posedge %clk label "past" : i1
  hw.output
}

// CHECK-LABEL: @explicit_clock(
// CHECK: verif.clocked_assert %a, posedge %clk label "atom"
hw.module @explicit_clock(in %clk: i1, in %a: i1) {
  %atom = ltl.clocked_atom %a, posedge %clk : i1
  verif.assert %atom label "atom" : !ltl.sequence
  hw.output
}

// CHECK-LABEL: @unconstrained(
// CHECK: seq.firreg
// CHECK-NOT: preset
// CHECK: hw.output
hw.module @unconstrained(in %clk: i1, in %d: i1, out q: i1) {
  %false = hw.constant false
  %true = hw.constant true
  %time = llhd.constant_time <0ns, 1d, 0e>
  %s = llhd.sig %false {llhd.unconstrained} : i1
  %q = llhd.prb %s : i1
  %value, %enable = llhd.process -> i1, i1 {
    cf.br ^wait(%false, %false : i1, i1)
  ^wait(%v: i1, %e: i1):
    llhd.wait yield (%v, %e : i1, i1), (%clk : i1), ^edge(%clk : i1)
  ^edge(%oldclk: i1):
    %notold = comb.xor %oldclk, %true : i1
    %rise = comb.and %notold, %clk : i1
    cf.cond_br %rise, ^wait(%d, %true : i1, i1), ^wait(%q, %false : i1, i1)
  }
  llhd.drv %s, %value after %time if %enable : i1
  hw.output %q : i1
}

// CHECK-LABEL: @raw_nonblocking(
// CHECK: verif.clocked_assert {{.*}}, posedge %clk label "raw_before"
// CHECK: verif.clocked_cover {{.*}}, posedge %clk label "raw_after"
// CHECK: seq.firreg {{.*}} preset 1 : i1
hw.module @raw_nonblocking(in %clk: i1, in %d: i1) {
  %true = hw.constant true
  %time = llhd.constant_time <0ns, 1d, 0e>
  %s = llhd.sig %true : i1
  llhd.process {
    cf.br ^wait
  ^wait:
    llhd.wait (%clk : i1), ^edge(%clk : i1)
  ^edge(%old: i1):
    %notold = comb.xor %old, %true : i1
    %rise = comb.and %notold, %clk : i1
    cf.cond_br %rise, ^body, ^wait
  ^body:
    %before = llhd.prb %s : i1
    llhd.drv %s, %d after %time : i1
    verif.assert %before label "raw_before" : i1
    %after = llhd.prb %s : i1
    %notafter = comb.xor %after, %true : i1
    verif.cover %notafter label "raw_after" : i1
    cf.br ^wait
  }
  hw.output
}
