// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=unrealized_conversion_cast

// Convert module ports, instance results and pure time/int conversions together.
// CHECK-LABEL: hw.module @time_ports(in %value : i64, out stored : i64, out bits : i64)
// CHECK: [[STORED:%.+]] = hw.instance "child" @time_identity(value: %value: i64) -> (stored: i64)
// CHECK: hw.output [[STORED]], [[STORED]] : i64, i64
hw.module @time_ports(in %value: !llhd.time, out stored: !llhd.time, out bits: i64) {
  %stored = hw.instance "child" @time_identity(value: %value: !llhd.time) -> (stored: !llhd.time)
  %bits = llhd.time_to_int %stored
  %roundtrip = llhd.int_to_time %bits
  hw.output %roundtrip, %bits : !llhd.time, i64
}
// CHECK-LABEL: hw.module @time_identity(in %value : i64, out stored : i64)
// CHECK-NEXT: hw.output %value : i64
hw.module @time_identity(in %value: !llhd.time, out stored: !llhd.time) {
  hw.output %value : !llhd.time
}
// Unused external ports also lose LLHD types.
// CHECK-LABEL: hw.module.extern @time_external(in %value : i64, out stored : i64)
hw.module.extern @time_external(in %value: !llhd.time, out stored: !llhd.time)

// Every supported SI unit uses the same femtosecond encoding. Accept all 64
// unsigned bits, including the maximum value, without signed truncation.
// CHECK-LABEL: @time_units(
// CHECK-DAG: [[FS:%.+]] = hw.constant 1 : i64
// CHECK-DAG: [[PS:%.+]] = hw.constant 1000 : i64
// CHECK-DAG: [[NS:%.+]] = hw.constant 1000000 : i64
// CHECK-DAG: [[US:%.+]] = hw.constant 1000000000 : i64
// CHECK-DAG: [[MS:%.+]] = hw.constant 1000000000000 : i64
// CHECK-DAG: [[S:%.+]] = hw.constant 1000000000000000 : i64
// CHECK-DAG: [[MAX:%.+]] = hw.constant -1 : i64
// CHECK: hw.output [[FS]], [[PS]], [[NS]], [[US]], [[MS]], [[S]], [[MAX]] : i64, i64, i64, i64, i64, i64, i64
hw.module @time_units(out fs: !llhd.time, out ps: !llhd.time, out ns: !llhd.time, out us: !llhd.time, out ms: !llhd.time, out s: !llhd.time, out max: !llhd.time) {
  %fs = llhd.constant_time <1fs, 0d, 0e>
  %ps = llhd.constant_time <1ps, 0d, 0e>
  %ns = llhd.constant_time <1ns, 0d, 0e>
  %us = llhd.constant_time <1us, 0d, 0e>
  %ms = llhd.constant_time <1ms, 0d, 0e>
  %s = llhd.constant_time <1s, 0d, 0e>
  %max = llhd.constant_time <18446744073709551615fs, 0d, 0e>
  hw.output %fs, %ps, %ns, %us, %ms, %s, %max : !llhd.time, !llhd.time, !llhd.time, !llhd.time, !llhd.time, !llhd.time, !llhd.time
}

// A shared zero has distinct data and scheduling uses. Keep its LLHD scheduling
// representation until signal lowering consumes it, rather than converting a
// drive's delay to i64 or losing the data use.
// CHECK-LABEL: @shared_zero(in %clk : i1, in %value : i64, out stored : i64, out zero : i64)
// CHECK: [[ZERO:%.+]] = hw.constant 0 : i64
// CHECK: [[REG:%.+]] = seq.firreg %value clock {{%.+}} : i64
// CHECK: hw.output [[REG]], [[ZERO]] : i64, i64
hw.module @shared_zero(in %clk: i1, in %value: i64, out stored: !llhd.time, out zero: !llhd.time) {
  %zero = llhd.constant_time <0ns, 0d, 0e>
  %true = hw.constant true
  %sig = llhd.sig %zero {llhd.unconstrained} : !llhd.time
  llhd.process {
    cf.br ^wait
  ^wait:
    llhd.wait (%clk : i1), ^edge(%clk : i1)
  ^edge(%old: i1):
    %notOld = comb.xor bin %old, %true : i1
    %posedge = comb.and bin %notOld, %clk : i1
    cf.cond_br %posedge, ^update, ^wait
  ^update:
    %time = llhd.int_to_time %value
    llhd.drv %sig, %time after %zero : !llhd.time
    cf.br ^wait
  }
  %stored = llhd.prb %sig : !llhd.time
  hw.output %stored, %zero : !llhd.time, !llhd.time
}

// Region result types and branch/block arguments must agree after conversion.
// CHECK-LABEL: @time_cfg(in %value : i64, out stored : i64)
// CHECK-NEXT: hw.output %value : i64
hw.module @time_cfg(in %value: !llhd.time, out stored: !llhd.time) {
  %stored = llhd.combinational -> !llhd.time {
    cf.br ^next(%value : !llhd.time)
  ^next(%arg: !llhd.time):
    llhd.yield %arg : !llhd.time
  }
  hw.output %stored : !llhd.time
}

// Nested data types must be converted too, including handwritten struct fields.
// CHECK-LABEL: hw.module @time_aggregates(in %array : !hw.array<2xi64>, in %struct : !hw.struct<t: i64, valid: i1>, in %union : !hw.union<t: i64, bits: i64>, out array : !hw.array<2xi64>, out struct : !hw.struct<t: i64, valid: i1>, out union : !hw.union<t: i64, bits: i64>)
// CHECK-NEXT: hw.output %array, %struct, %union
hw.module @time_aggregates(in %array: !hw.array<2x!llhd.time>, in %struct: !hw.struct<t: !llhd.time, valid: i1>, in %union: !hw.union<t: !llhd.time, bits: i64>, out array: !hw.array<2x!llhd.time>, out struct: !hw.struct<t: !llhd.time, valid: i1>, out union: !hw.union<t: !llhd.time, bits: i64>) {
  hw.output %array, %struct, %union : !hw.array<2x!llhd.time>, !hw.struct<t: !llhd.time, valid: i1>, !hw.union<t: !llhd.time, bits: i64>
}
