// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset

// Export the value of locally owned state without exporting its storage.
// CHECK-LABEL: hw.module @source(in %clk : !seq.clock, in %d : i1, out q : i1)
// CHECK: [[Q:%.+]] = seq.firreg %d clock %clk : i1
// CHECK-NEXT: hw.output [[Q]] : i1
hw.module @source(in %clk: !seq.clock, in %d: i1, out q: !llhd.ref<i1>) {
  %false = hw.constant false
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = llhd.sig %false {llhd.unconstrained} : i1
  %value = seq.firreg %d clock %clk : i1
  llhd.drv %q, %value after %time : i1
  hw.output %q : !llhd.ref<i1>
}

// Read-only references can be forwarded through both output and input ports.
// CHECK-LABEL: hw.module @forward
// CHECK: [[Q:%.+]] = hw.instance "source" @source(clk: %clk: !seq.clock, d: %d: i1) -> (q: i1)
// CHECK-NEXT: hw.output [[Q]] : i1
hw.module @forward(in %clk: !seq.clock, in %d: i1, out q: !llhd.ref<i1>) {
  %q = hw.instance "source" @source(clk: %clk: !seq.clock, d: %d: i1) -> (q: !llhd.ref<i1>)
  hw.output %q : !llhd.ref<i1>
}

// CHECK-LABEL: hw.module @read(in %q : i1, out y : i1)
// CHECK-NEXT: hw.output %q : i1
hw.module @read(in %q: !llhd.ref<i1>, out y: i1) {
  %y = llhd.prb %q : i1
  hw.output %y : i1
}

// CHECK-LABEL: hw.module @top
// CHECK: [[Q:%.+]] = hw.instance "forward" @forward(clk: %clk: !seq.clock, d: %d: i1) -> (q: i1)
// CHECK: [[Y:%.+]] = hw.instance "read" @read(q: [[Q]]: i1) -> (y: i1)
// CHECK-NEXT: hw.output [[Y]] : i1
hw.module @top(in %clk: !seq.clock, in %d: i1, out y: i1) {
  %q = hw.instance "forward" @forward(clk: %clk: !seq.clock, d: %d: i1) -> (q: !llhd.ref<i1>)
  %y = hw.instance "read" @read(q: %q: !llhd.ref<i1>) -> (y: i1)
  hw.output %y : i1
}

// A local signal passed to a reference input must be probed at the instance.
// CHECK-LABEL: hw.module @local_input
// CHECK: [[Y:%.+]] = hw.instance "read" @read(q: %d: i1) -> (y: i1)
// CHECK-NEXT: hw.output [[Y]] : i1
hw.module @local_input(in %d: i1, out y: i1) {
  %false = hw.constant false
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = llhd.sig %false {llhd.unconstrained} : i1
  llhd.drv %q, %d after %time : i1
  %y = hw.instance "read" @read(q: %q: !llhd.ref<i1>) -> (y: i1)
  hw.output %y : i1
}

// Register feedback across a reference port is a valid sequential circuit.
// CHECK-LABEL: hw.module @feedback
// CHECK: [[Q:%.+]] = hw.instance "source" @source(clk: %clk: !seq.clock, d: [[Q]]: i1) -> (q: i1)
// CHECK-NEXT: hw.output [[Q]] : i1
hw.module @feedback(in %clk: !seq.clock, out q: i1) {
  %q_ref = hw.instance "source" @source(clk: %clk: !seq.clock, d: %q: i1) -> (q: !llhd.ref<i1>)
  %q = llhd.prb %q_ref : i1
  hw.output %q : i1
}
