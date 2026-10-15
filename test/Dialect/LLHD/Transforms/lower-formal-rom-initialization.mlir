// RUN: circt-opt %s --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %s --lower-llhd-formal-to-core --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.

// Ordinary signal promotion may represent startup writes using a process value
// and a drive-enable result. Both must fold away for a constant ROM.
// CHECK-LABEL: hw.module @rom(
// CHECK: [[ROM:%.+]] = hw.aggregate_constant [10 : i8, 5 : i8, 2 : i8, 1 : i8] : !hw.array<4xi8>
// CHECK: [[Q:%.+]] = hw.array_get [[ROM]][%address] : !hw.array<4xi8>, i2
// CHECK-NEXT: hw.output [[Q]] : i8
hw.module @rom(in %address: i2, out q: i8) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [0 : i8, 0 : i8, 0 : i8, 0 : i8] : !hw.array<4xi8>
  %data = llhd.sig %init {llhd.unconstrained} : !hw.array<4xi8>
  %startup:2 = llhd.process -> !hw.array<4xi8>, i1 {
    %rom = hw.aggregate_constant [10 : i8, 5 : i8, 2 : i8, 1 : i8] : !hw.array<4xi8>
    %enable = hw.constant true
    llhd.halt %rom, %enable : !hw.array<4xi8>, i1
  }
  llhd.drv %data, %startup#0 after %time if %startup#1 : !hw.array<4xi8>
  %contents = llhd.prb %data : !hw.array<4xi8>
  %q = hw.array_get %contents[%address] : !hw.array<4xi8>, i2
  hw.output %q : i8
}
