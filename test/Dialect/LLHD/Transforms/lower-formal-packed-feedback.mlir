// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s
// RUN: circt-opt %s --lower-llhd-formal-to-core --canonicalize --cse --lower-llhd-formal-to-core | FileCheck %s

// The complete packed output stays observable. Extracting the high lane must
// not create a dependency on the low lane, which comes from the child output.
// CHECK-LABEL: hw.module @Top(in %ack : i1
// CHECK: [[READY:%.+]] = hw.instance "relay" @Relay(ack: %ack: i1)
// CHECK: hw.output [[READY]], {{.*}} : i1, i2
hw.module @Top(in %ack: i1, out ready: i1, out packed: i2) {
  %false = hw.constant false
  %high = comb.concat %ack, %false : i1, i1
  %low = comb.concat %false, %ready : i1, i1
  %packed = comb.or bin %high, %low : i2
  %next = comb.extract %packed from 1 : (i2) -> i1
  %ready = hw.instance "relay" @Relay(ack: %next: i1) -> (ready: i1)
  hw.output %ready, %packed : i1, i2
}
hw.module @Relay(in %ack: i1, out ready: i1) {
  hw.output %ack : i1
}

// Wider lanes, nonzero offset, and slices across concatenation boundaries.
// CHECK-LABEL: hw.module @Wide(in %ack : i3
// CHECK: [[READY:%.+]] = hw.instance "wide_relay" @WideRelay(ack: %ack: i3)
// CHECK: comb.extract %ack from 0 : (i3) -> i1
// CHECK: comb.extract [[READY]] from 2 : (i3) -> i1
// CHECK: hw.output [[READY]], {{.*}} : i3, i8, i4
hw.module @Wide(in %ack: i3, out ready: i3, out packed: i8, out span: i4) {
  %zero5 = hw.constant 0 : i5
  %high = comb.concat %ack, %zero5 : i3, i5
  %low = comb.concat %zero5, %ready : i5, i3
  %packed = comb.or bin %high, %low : i8
  %next = comb.extract %packed from 5 : (i8) -> i3
  %ready = hw.instance "wide_relay" @WideRelay(ack: %next: i3) -> (ready: i3)
  %span = comb.extract %packed from 2 : (i8) -> i4
  hw.output %ready, %packed, %span : i3, i8, i4
}
hw.module @WideRelay(in %ack: i3, out ready: i3) {
  hw.output %ack : i3
}

// The low lane is independent of the high feedback lane too. Nested ORs may
// be flattened by cleanup, but slicing must still expose all independent bits.
// CHECK-LABEL: hw.module @Low(in %ack : i2
// CHECK: [[READY:%.+]] = hw.instance "low_relay" @LowRelay(ack: %ack: i2)
// CHECK: hw.output [[READY]], {{.*}} : i2, i6
hw.module @Low(in %ack: i2, out ready: i2, out packed: i6) {
  %zero2 = hw.constant 0 : i2
  %zero4 = hw.constant 0 : i4
  %high = comb.concat %ready, %zero4 : i2, i4
  %middle = comb.concat %zero2, %ack, %zero2 : i2, i2, i2
  %low = comb.concat %zero4, %ack : i4, i2
  %pair = comb.or %high, %middle : i6
  %packed = comb.or %pair, %low : i6
  %next = comb.extract %packed from 0 : (i6) -> i2
  %ready = hw.instance "low_relay" @LowRelay(ack: %next: i2) -> (ready: i2)
  hw.output %ready, %packed : i2, i6
}
hw.module @LowRelay(in %ack: i2, out ready: i2) {
  hw.output %ack : i2
}

// Preserve the twoState flag and arbitrary attributes when cloning the slices
// and the narrower OR, without assuming binary logic on four-state operations.
// CHECK-LABEL: hw.module @Attributes(
// CHECK: [[A:%.+]] = comb.extract %a from 2 {test.tag = "slice"} : (i8) -> i3
// CHECK: [[B:%.+]] = comb.extract %b from 2 {test.tag = "slice"} : (i8) -> i3
// CHECK: [[NARROW:%.+]] = comb.or bin [[A]], [[B]] {test.tag = "or"} : i3
// CHECK: hw.output {{.*}}, [[NARROW]] : i8, i3
hw.module @Attributes(in %a: i8, in %b: i8, out packed: i8, out slice: i3) {
  %packed = comb.or bin %a, %b {test.tag = "or"} : i8
  %slice = comb.extract %packed from 2 {test.tag = "slice"} : (i8) -> i3
  hw.output %packed, %slice : i8, i3
}
// CHECK-LABEL: hw.module @FourState(
// CHECK: [[A:%.+]] = comb.extract %a from 3 : (i8) -> i2
// CHECK: [[B:%.+]] = comb.extract %b from 3 : (i8) -> i2
// CHECK: [[NARROW:%.+]] = comb.or [[A]], [[B]] {test.tag = "or4"} : i2
// CHECK: hw.output {{.*}}, [[NARROW]] : i8, i2
hw.module @FourState(in %a: i8, in %b: i8, out packed: i8, out slice: i2) {
  %packed = comb.or %a, %b {test.tag = "or4"} : i8
  %slice = comb.extract %packed from 3 : (i8) -> i2
  hw.output %packed, %slice : i8, i2
}

// A registered child cuts even feedback from the selected packed lane.
// CHECK-LABEL: hw.module @RegisteredFeedback(
// CHECK: [[READY:%.+]] = hw.instance "reg" @RegisteredRelay(clk: %clk: !seq.clock, ack: [[READY]]: i1)
// CHECK: hw.output [[READY]], {{.*}} : i1, i2
hw.module @RegisteredFeedback(in %clk: !seq.clock, in %ack: i1, out ready: i1, out packed: i2) {
  %false = hw.constant false
  %high = comb.concat %ack, %false : i1, i1
  %low = comb.concat %false, %ready : i1, i1
  %packed = comb.or bin %high, %low : i2
  %next = comb.extract %packed from 0 : (i2) -> i1
  %ready = hw.instance "reg" @RegisteredRelay(clk: %clk: !seq.clock, ack: %next: i1) -> (ready: i1)
  hw.output %ready, %packed : i1, i2
}
hw.module @RegisteredRelay(in %clk: !seq.clock, in %ack: i1, out ready: i1) {
  %ready = seq.compreg %ack, %clk : i1
  hw.output %ready : i1
}
