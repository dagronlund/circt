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
