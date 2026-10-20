// RUN: circt-opt %s --lower-llhd-formal-to-core --verify-diagnostics

// Only one of two elements is assigned. The other element's actual feedback
// must remain visible after factoring the conditional update.
hw.module @incomplete_update(in %select: i1, in %a: i8, in %b: i8, out q: !hw.array<2xi8>) {
  %zero = hw.constant false
  %left = hw.array_inject %q[%zero], %a : !hw.array<2xi8>, i1
  %right = hw.array_inject %q[%zero], %b : !hw.array<2xi8>, i1
  // expected-error @+1 {{combinational dependency cycle in formal hardware}}
  %q = comb.mux %select, %left, %right : !hw.array<2xi8>
  hw.output %q : !hw.array<2xi8>
}
