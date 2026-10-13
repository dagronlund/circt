// RUN: circt-opt %s --llhd-mem2reg --canonicalize --cse | FileCheck %s --implicit-check-not=llhd.sig.array_slice

// Projection reads use the selected subarray of the current reaching value.
// CHECK-LABEL: hw.module @probe(
// CHECK: [[Q:%.+]] = hw.array_slice %u[%offset] : (!hw.array<4xi3>) -> !hw.array<2xi3>
// CHECK: hw.output [[Q]] : !hw.array<2xi3>
hw.module @probe(in %u: !hw.array<4xi3>, in %offset: i2, out q: !hw.array<2xi3>) {
  %q = llhd.combinational -> !hw.array<2xi3> {
    %signal = llhd.sig %u : !hw.array<4xi3>
    %slice = llhd.sig.array_slice %signal at %offset : <!hw.array<4xi3>> -> <!hw.array<2xi3>>
    %value = llhd.prb %slice : !hw.array<2xi3>
    llhd.yield %value : !hw.array<2xi3>
  }
  hw.output %q : !hw.array<2xi3>
}

// Element indices are widened before multiplication by a non-power-of-two
// element width. Bits outside the replacement mask come from the old value.
// CHECK-LABEL: hw.module @drive(
// CHECK-DAG: [[STRIDE:%.+]] = hw.constant 3 : i12
// CHECK-DAG: [[MASK:%.+]] = hw.constant 63 : i12
// CHECK: [[BASE:%.+]] = hw.bitcast %u : (!hw.array<4xi3>) -> i12
// CHECK: [[REPLACEMENT:%.+]] = hw.bitcast %v : (!hw.array<2xi3>) -> i6
// CHECK: [[EXT:%.+]] = comb.concat {{%.+}}, %offset : i10, i2
// CHECK: [[OFFSET:%.+]] = comb.mul [[EXT]], [[STRIDE]] : i12
// CHECK: [[SHIFTED_MASK:%.+]] = comb.shl [[MASK]], [[OFFSET]] : i12
// CHECK: [[INVERSE_MASK:%.+]] = comb.xor bin [[SHIFTED_MASK]], {{%.+}} : i12
// CHECK: [[OLD:%.+]] = comb.and [[BASE]], [[INVERSE_MASK]] : i12
// CHECK: [[EXT_REPLACEMENT:%.+]] = comb.concat {{%.+}}, [[REPLACEMENT]] : i6, i6
// CHECK: [[NEW:%.+]] = comb.shl [[EXT_REPLACEMENT]], [[OFFSET]] : i12
// CHECK: [[UPDATED:%.+]] = comb.or [[OLD]], [[NEW]] : i12
// CHECK: [[Q:%.+]] = hw.bitcast [[UPDATED]] : (i12) -> !hw.array<4xi3>
// CHECK: hw.output [[Q]] : !hw.array<4xi3>
hw.module @drive(in %u: !hw.array<4xi3>, in %v: !hw.array<2xi3>, in %offset: i2,
                 out q: !hw.array<4xi3>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = llhd.combinational -> !hw.array<4xi3> {
    %signal = llhd.sig %u : !hw.array<4xi3>
    %slice = llhd.sig.array_slice %signal at %offset : <!hw.array<4xi3>> -> <!hw.array<2xi3>>
    llhd.drv %slice, %v after %time : !hw.array<2xi3>
    %value = llhd.prb %signal : !hw.array<4xi3>
    llhd.yield %value : !hw.array<4xi3>
  }
  hw.output %q : !hw.array<4xi3>
}

// A conditional drive reads the old slice for its disabled arm.
// CHECK-LABEL: hw.module @conditional(
// CHECK: [[OLD:%.+]] = hw.array_slice %u[%offset] : (!hw.array<4xi3>) -> !hw.array<2xi3>
// CHECK: [[REPLACEMENT:%.+]] = comb.mux %enable, %v, [[OLD]] : !hw.array<2xi3>
// CHECK: hw.bitcast [[REPLACEMENT]] : (!hw.array<2xi3>) -> i6
hw.module @conditional(in %u: !hw.array<4xi3>, in %v: !hw.array<2xi3>,
                       in %offset: i2, in %enable: i1, out q: !hw.array<4xi3>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = llhd.combinational -> !hw.array<4xi3> {
    %signal = llhd.sig %u : !hw.array<4xi3>
    %slice = llhd.sig.array_slice %signal at %offset : <!hw.array<4xi3>> -> <!hw.array<2xi3>>
    llhd.drv %slice, %v after %time if %enable : !hw.array<2xi3>
    %value = llhd.prb %signal : !hw.array<4xi3>
    llhd.yield %value : !hw.array<4xi3>
  }
  hw.output %q : !hw.array<4xi3>
}

// Projection stacks can contain both a slice and an element access.
// CHECK-LABEL: hw.module @nested(
// CHECK: [[SLICE:%.+]] = hw.array_slice %u[%offset]
// CHECK: [[UPDATED:%.+]] = hw.array_inject [[SLICE]][%index], %v : !hw.array<2xi3>, i1
// CHECK: hw.bitcast [[UPDATED]] : (!hw.array<2xi3>) -> i6
hw.module @nested(in %u: !hw.array<4xi3>, in %v: i3, in %offset: i2,
                  in %index: i1, out q: !hw.array<4xi3>) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = llhd.combinational -> !hw.array<4xi3> {
    %signal = llhd.sig %u : !hw.array<4xi3>
    %slice = llhd.sig.array_slice %signal at %offset : <!hw.array<4xi3>> -> <!hw.array<2xi3>>
    %element = llhd.sig.array_get %slice[%index] : <!hw.array<2xi3>>
    llhd.drv %element, %v after %time : i3
    %value = llhd.prb %signal : !hw.array<4xi3>
    llhd.yield %value : !hw.array<4xi3>
  }
  hw.output %q : !hw.array<4xi3>
}

// Zero-width elements must not produce invalid offset arithmetic.
// CHECK-LABEL: hw.module @zero_width(
// CHECK-NEXT: hw.output %u, %v, %offset : !hw.array<4xi0>, !hw.array<2xi0>, i2
hw.module @zero_width(in %u: !hw.array<4xi0>, in %v: !hw.array<2xi0>,
                      in %offset: i2, out q: !hw.array<4xi0>,
                      out echo_v: !hw.array<2xi0>, out echo_offset: i2) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %q = llhd.combinational -> !hw.array<4xi0> {
    %signal = llhd.sig %u : !hw.array<4xi0>
    %slice = llhd.sig.array_slice %signal at %offset : <!hw.array<4xi0>> -> <!hw.array<2xi0>>
    llhd.drv %slice, %v after %time : !hw.array<2xi0>
    %value = llhd.prb %signal : !hw.array<4xi0>
    llhd.yield %value : !hw.array<4xi0>
  }
  hw.output %q, %v, %offset : !hw.array<4xi0>, !hw.array<2xi0>, i2
}
