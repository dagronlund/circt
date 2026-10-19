// RUN: circt-opt %s --lower-llhd-formal-to-core --split-input-file --verify-diagnostics

// A packed cast must not hide an actual read of an undriven upper lane.
hw.module @ObservedUpper(in %data: i3, out q: i5) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [0 : i8] : !hw.array<1xi8>
  %index = hw.constant 0 : i0
  %low = hw.constant 0 : i3
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : !hw.array<1xi8>
  %element = llhd.sig.array_get %s[%index] : <!hw.array<1xi8>>
  %bits = llhd.sig.extract %element from %low : <i8> -> <i3>
  llhd.drv %bits, %data after %time : i3
  %value = llhd.prb %s : !hw.array<1xi8>
  %packed = hw.bitcast %value : (!hw.array<1xi8>) -> i8
  %q = comb.extract %packed from 3 : (i8) -> i5
  hw.output %q : i5
}

// -----

// A slice spanning driven and undriven bits still observes undriven storage.
hw.module @SpanningUndriven(in %data: i3, out q: i3) {
  %time = llhd.constant_time <0ns, 0d, 1e>
  %init = hw.aggregate_constant [0 : i8] : !hw.array<1xi8>
  %index = hw.constant 0 : i0
  %low = hw.constant 0 : i3
  // expected-error @+1 {{signal must have exactly one resolved driver}}
  %s = llhd.sig %init {llhd.unconstrained} : !hw.array<1xi8>
  %element = llhd.sig.array_get %s[%index] : <!hw.array<1xi8>>
  %bits = llhd.sig.extract %element from %low : <i8> -> <i3>
  llhd.drv %bits, %data after %time : i3
  %value = llhd.prb %s : !hw.array<1xi8>
  %packed = hw.bitcast %value : (!hw.array<1xi8>) -> i8
  %q = comb.extract %packed from 2 : (i8) -> i3
  hw.output %q : i3
}
