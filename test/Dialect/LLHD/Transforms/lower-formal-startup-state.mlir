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

// A one-shot constant assignment supplies the original scalar initial state,
// even if the declaration only supplied an unconstrained scheduling value.
// CHECK-LABEL: hw.module @constant_startup
// CHECK: [[Q:%.+]] = seq.firreg %data clock %clk preset 7 : i8
// CHECK-NEXT: hw.output [[Q]] : i8
hw.module @constant_startup(in %clk: !seq.clock, in %data: i8, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %zero = hw.constant 0 : i8
  %seven = hw.constant 7 : i8
  %s = llhd.sig %zero {llhd.unconstrained} : i8
  llhd.drv %s, %seven after %time {llhd.initial} : i8
  %reg = seq.firreg %data clock %clk : i8
  llhd.drv %s, %reg after %time : i8
  %q = llhd.prb %s : i8
  hw.output %q : i8
}

// Input-dependent startup is an initial constraint, not a constant preset.
// CHECK-LABEL: hw.module @runtime_input
// CHECK-DAG: [[ONE:%.+]] = hw.constant 1 : i8
// CHECK-DAG: [[ZERO:%.+]] = hw.constant false
// CHECK-DAG: [[INITIAL:%.+]] = comb.xor %data, [[ONE]] : i8
// CHECK-DAG: [[Q:%.+]] = seq.firreg %data clock %clk : i8
// CHECK-DAG: [[ACTIVE:%.+]] = seq.firreg [[ZERO]] clock %clk preset 1 : i1
// CHECK-DAG: [[EQUAL:%.+]] = comb.icmp eq [[Q]], [[INITIAL]] : i8
// CHECK-DAG: [[INACTIVE:%.+]] = comb.xor [[ACTIVE]], {{%.+}} : i1
// CHECK-DAG: [[CONSTRAINT:%.+]] = comb.or [[INACTIVE]], [[EQUAL]] : i1
// CHECK-DAG: verif.assume [[CONSTRAINT]] : i1
// CHECK: hw.output [[Q]] : i8
hw.module @runtime_input(in %clk: !seq.clock, in %data: i8, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %one = hw.constant 1 : i8
  %s = llhd.sig %one {llhd.explicit_init} : i8
  %old = llhd.prb %s : i8
  %startup = llhd.process -> i8 {
    %next = comb.xor %old, %data : i8
    llhd.halt %next : i8
  }
  llhd.drv %s, %startup after %time : i8
  %reg = seq.firreg %data clock %clk preset 1 : i8
  llhd.drv %s, %reg after %time : i8
  hw.output %old : i8
}

// Unrolled blocking writes read the preceding update, in procedural order.
// CHECK-LABEL: hw.module @sequential_startup
// CHECK: [[Q:%.+]] = seq.firreg %data clock %clk preset 4 : i8
// CHECK-NEXT: hw.output [[Q]] : i8
hw.module @sequential_startup(in %clk: !seq.clock, in %data: i8, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %three = hw.constant 3 : i8
  %one = hw.constant 1 : i8
  %two = hw.constant 2 : i8
  %s = llhd.sig %three {llhd.explicit_init} : i8
  llhd.process {
    %first = llhd.prb %s : i8
    %next = comb.xor %first, %one : i8
    llhd.drv %s, %next after %time : i8
    %second = llhd.prb %s : i8
    %final = comb.add %second, %two : i8
    llhd.drv %s, %final after %time : i8
    llhd.halt
  }
  %reg = seq.firreg %data clock %clk preset 3 : i8
  llhd.drv %s, %reg after %time : i8
  %q = llhd.prb %s : i8
  hw.output %q : i8
}

// Ordinary promotion can yield a drive-enable result, which must be proven
// true before the startup assignment can be absorbed.
// CHECK-LABEL: hw.module @startup_enable_result
// CHECK: [[Q:%.+]] = seq.firreg %data clock %clk preset 2 : i8
// CHECK-NEXT: hw.output [[Q]] : i8
hw.module @startup_enable_result(in %clk: !seq.clock, in %data: i8, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %three = hw.constant 3 : i8
  %one = hw.constant 1 : i8
  %true = hw.constant true
  %s = llhd.sig %three {llhd.explicit_init} : i8
  %old = llhd.prb %s : i8
  %startup:2 = llhd.process -> i8, i1 {
    %next = comb.xor %old, %one : i8
    llhd.halt %next, %true : i8, i1
  }
  llhd.drv %s, %startup#0 after %time if %startup#1 : i8
  %reg = seq.firreg %data clock %clk preset 3 : i8
  llhd.drv %s, %reg after %time : i8
  hw.output %old : i8
}
