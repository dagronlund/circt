// REQUIRES: libz3
// REQUIRES: circt-bmc-jit
// RUN: circt-opt %s --lower-llhd-formal-to-core -o %t
// RUN: circt-bmc %t --module=Checks -b 1 --shared-libs=%libz3 | FileCheck %s
// CHECK: Bound reached with no violations!

// Check every input combination symbolically. The packed producer remains a
// visible output, while its slices feed a child output appearing in another
// packed lane. Also check a slice spanning lanes and a differently sized slice
// spanning both boundaries against independently assembled expected values.
hw.module @Packing(in %ack: i3, out ready: i3, out packed: i8, out span: i4, out middle: i6) {
  %zero5 = hw.constant 0 : i5
  %high = comb.concat %ack, %zero5 : i3, i5
  %low = comb.concat %zero5, %ready : i5, i3
  %packed = comb.or bin %high, %low : i8
  %next = comb.extract %packed from 5 : (i8) -> i3
  %ready = hw.instance "relay" @Relay(ack: %next: i3) -> (ready: i3)
  %span = comb.extract %packed from 2 : (i8) -> i4
  %middle = comb.extract %packed from 1 : (i8) -> i6
  hw.output %ready, %packed, %span, %middle : i3, i8, i4, i6
}
hw.module @Relay(in %ack: i3, out ready: i3) {
  hw.output %ack : i3
}
hw.module @Checks(in %ack: i3) {
  %ready, %packed, %span, %middle = hw.instance "packing" @Packing(ack: %ack: i3) -> (ready: i3, packed: i8, span: i4, middle: i6)
  %zero2 = hw.constant 0 : i2
  %expected_packed = comb.concat %ack, %zero2, %ack : i3, i2, i3
  %ack_low = comb.extract %ack from 0 : (i3) -> i1
  %ack_high = comb.extract %ack from 2 : (i3) -> i1
  %expected_span = comb.concat %ack_low, %zero2, %ack_high : i1, i2, i1
  %ack_low2 = comb.extract %ack from 0 : (i3) -> i2
  %ack_high2 = comb.extract %ack from 1 : (i3) -> i2
  %expected_middle = comb.concat %ack_low2, %zero2, %ack_high2 : i2, i2, i2
  %ready_ok = comb.icmp bin eq %ready, %ack : i3
  %packed_ok = comb.icmp bin eq %packed, %expected_packed : i8
  %span_ok = comb.icmp bin eq %span, %expected_span : i4
  %middle_ok = comb.icmp bin eq %middle, %expected_middle : i6
  %ok = comb.and bin %ready_ok, %packed_ok, %span_ok, %middle_ok : i1
  verif.assert %ok : i1
  hw.output
}
