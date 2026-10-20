// RUN: circt-opt %s --verif-abstract-random | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %s --comb-assume-two-valued --verif-abstract-random | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %s --verif-abstract-random --comb-assume-two-valued | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %s --verif-abstract-random --verif-abstract-random | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %s --verif-abstract-random='assume-ranges=false' | FileCheck %s --check-prefix=UNBOUNDED --implicit-check-not=verif.assume --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %s --verif-abstract-random | FileCheck %s --check-prefix=NOOP

func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
// CHECK: func.func private @unrelated(i32) -> i32
func.func private @unrelated(i32) -> i32

// Two draws remain distinct; copies of one draw share a source. Both endpoint
// orderings of the full-width interval need no range assumptions.
// CHECK-LABEL: hw.module @full_width(
// CHECK: [[B:%.+]] = verif.symbolic_value : i32
// CHECK: [[A:%.+]] = verif.symbolic_value : i32
// CHECK-NOT: verif.assume
// CHECK: [[VALUES:%.+]]:2 = llhd.combinational -> i32, i32 {
// CHECK-NEXT: llhd.yield [[A]], [[B]] : i32, i32
// CHECK: hw.output [[VALUES]]#0, [[VALUES]]#0, [[VALUES]]#1 : i32, i32, i32
// UNBOUNDED-LABEL: hw.module @full_width(
// UNBOUNDED-COUNT-2: verif.symbolic_value : i32
hw.module @full_width(out a: i32, out copy: i32, out b: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %a, %b = llhd.combinational -> i32, i32 {
    %a = func.call @__circt_urandom_range(%zero, %max, %null) : (i32, i32, !llvm.ptr) -> i32
    %b = func.call @__circt_urandom_range(%max, %zero, %null) : (i32, i32, !llvm.ptr) -> i32
    llhd.yield %a, %b : i32, i32
  }
  hw.output %a, %a, %b : i32, i32, i32
}

// Assumptions stay in the call's conditional block, with unsigned normalization
// and two-state Comb operations even when the two-value pass ran earlier.
// CHECK-LABEL: hw.module @conditional(
// CHECK: [[DRAW:%.+]] = verif.symbolic_value : i32
// CHECK: llhd.combinational -> i32 {
// CHECK-NEXT: cf.cond_br %enable, ^bb1, ^bb2
// CHECK-NEXT: ^bb1:
// CHECK-NEXT: [[ORDER:%.+]] = comb.icmp bin ule %low, %high : i32
// CHECK-NEXT: [[LOW:%.+]] = comb.mux bin [[ORDER]], %low, %high : i32
// CHECK-NEXT: [[HIGH:%.+]] = comb.mux bin [[ORDER]], %high, %low : i32
// CHECK-NEXT: [[ABOVE:%.+]] = comb.icmp bin ule [[LOW]], [[DRAW]] : i32
// CHECK-NEXT: [[BELOW:%.+]] = comb.icmp bin ule [[DRAW]], [[HIGH]] : i32
// CHECK-NEXT: [[RANGE:%.+]] = comb.and bin [[ABOVE]], [[BELOW]] : i1
// CHECK-NEXT: verif.assume [[RANGE]] : i1
// CHECK-NEXT: llhd.yield [[DRAW]] : i32
// CHECK-NEXT: ^bb2:
// UNBOUNDED-LABEL: hw.module @conditional(
// UNBOUNDED: [[DRAW:%.+]] = verif.symbolic_value : i32
// UNBOUNDED: cf.cond_br %enable, ^bb1, ^bb2
// UNBOUNDED-NEXT: ^bb1:
// UNBOUNDED-NEXT: llhd.yield [[DRAW]] : i32
hw.module @conditional(in %enable: i1, in %low: i32, in %high: i32, out value: i32) {
  %zero = hw.constant 0 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %value = llhd.combinational -> i32 {
    cf.cond_br %enable, ^draw, ^idle
  ^draw:
    %draw = func.call @__circt_urandom_range(%low, %high, %null) : (i32, i32, !llvm.ptr) -> i32
    llhd.yield %draw : i32
  ^idle:
    llhd.yield %zero : i32
  }
  hw.output %value : i32
}

// The ordinary seed assignment, probe, region and unrelated call remain.
// CHECK-LABEL: hw.module @raw_seed(
// CHECK: [[DRAW:%.+]] = verif.symbolic_value : i32
// CHECK: [[SEED:%.+]] = llhd.sig
// CHECK: llhd.combinational -> i32, i32 {
// CHECK-NEXT: llhd.drv [[SEED]], %seed_in after {{%.+}} : i32
// CHECK-NEXT: [[PRIOR:%.+]] = llhd.prb [[SEED]] : i32
// CHECK-NEXT: [[OTHER:%.+]] = func.call @unrelated([[DRAW]]) : (i32) -> i32
// CHECK-NEXT: llhd.yield [[OTHER]], [[PRIOR]] : i32, i32
// UNBOUNDED-LABEL: hw.module @raw_seed(
// UNBOUNDED: verif.symbolic_value : i32
hw.module @raw_seed(in %seed_in: i32, out value: i32, out seed_out: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %one = hw.constant 1 : i32
  %epsilon = llhd.constant_time <0ns, 0d, 1e>
  %seed = llhd.sig %zero : i32
  %value, %seed_out = llhd.combinational -> i32, i32 {
    llhd.drv %seed, %seed_in after %epsilon : i32
    %prior = llhd.prb %seed : i32
    %tmp = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
    llvm.store %prior, %tmp : i32, !llvm.ptr
    %draw = func.call @__circt_urandom_range(%zero, %max, %tmp) : (i32, i32, !llvm.ptr) -> i32
    %next = llvm.load %tmp : !llvm.ptr -> i32
    llhd.drv %seed, %next after %epsilon : i32
    %other = func.call @unrelated(%draw) : (i32) -> i32
    llhd.yield %other, %prior : i32, i32
  }
  hw.output %value, %seed_out : i32, i32
}

// Forward promoted seed results without requiring a signal probe or attributes.
// CHECK-LABEL: hw.module @promoted_seed(
// CHECK: [[DRAW:%.+]] = verif.symbolic_value : i32
// CHECK: llhd.combinational -> i32, i32 {
// CHECK-NEXT: llhd.yield [[DRAW]], %seed_in : i32, i32
// UNBOUNDED-LABEL: hw.module @promoted_seed(
// UNBOUNDED: verif.symbolic_value : i32
hw.module @promoted_seed(in %seed_in: i32, out value: i32, out seed_out: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %one = hw.constant 1 : i32
  %value, %seed_out = llhd.combinational -> i32, i32 {
    %tmp = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
    llvm.store %seed_in, %tmp : i32, !llvm.ptr
    %draw = func.call @__circt_urandom_range(%zero, %max, %tmp) : (i32, i32, !llvm.ptr) -> i32
    %next = llvm.load %tmp : !llvm.ptr -> i32
    llhd.yield %draw, %next : i32, i32
  }
  hw.output %value, %seed_out : i32, i32
}

// Cleanup may already have dropped an unused post-call seed load.
// CHECK-LABEL: hw.module @unused_seed(
// CHECK: [[DRAW:%.+]] = verif.symbolic_value : i32
// CHECK: llhd.combinational -> i32 {
// CHECK-NEXT: llhd.yield [[DRAW]] : i32
// UNBOUNDED-LABEL: hw.module @unused_seed(
// UNBOUNDED: verif.symbolic_value : i32
hw.module @unused_seed(in %seed_in: i32, out value: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %one = hw.constant 1 : i32
  %value = llhd.combinational -> i32 {
    %tmp = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
    llvm.store %seed_in, %tmp : i32, !llvm.ptr
    %draw = func.call @__circt_urandom_range(%zero, %max, %tmp) : (i32, i32, !llvm.ptr) -> i32
    llhd.yield %draw : i32
  }
  hw.output %value : i32
}

// No matching calls: do not clean up unrelated dead operations.
// CHECK-LABEL: hw.module @unrelated_only(
// UNBOUNDED-LABEL: hw.module @unrelated_only(
// NOOP-LABEL: hw.module @unrelated_only(
// NOOP-NEXT: %c7_i32 = hw.constant 7 : i32
// NOOP-NEXT: hw.output
hw.module @unrelated_only() {
  %unused = hw.constant 7 : i32
  hw.output
}
