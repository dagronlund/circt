// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-opt %s --lower-llhd-formal-to-core --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.

// Evaluate a startup read from the declaration value. Preserve the register's
// runtime input and attributes while refining its preset from 3 to 2.
// CHECK-LABEL: hw.module @startup
// CHECK: [[Q:%.+]] = seq.firreg %data clock %clk preset 2 {test.tag = "state"} : i8
// CHECK-NEXT: hw.output [[Q]] : i8
hw.module @startup(in %clk: !seq.clock, in %data: i8, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %three = hw.constant 3 : i8
  %one = hw.constant 1 : i8
  %s = llhd.sig %three {llhd.explicit_init} : i8
  %old = llhd.prb %s : i8
  %startup = llhd.process -> i8 {
    %next = comb.xor %old, %one : i8
    llhd.halt %next : i8
  }
  llhd.drv %s, %startup after %time : i8
  %reg = seq.firreg %data clock %clk preset 3 {test.tag = "state"} : i8
  llhd.drv %s, %reg after %time : i8
  hw.output %old : i8
}
