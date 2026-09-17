// RUN: circt-opt %s --convert-moore-to-core --verify-roundtrip | FileCheck %s
// RUN: circt-opt %s --convert-moore-to-core | FileCheck %s --check-prefix=NO-MOORE

// NO-MOORE-NOT: moore.
// NO-MOORE: module
// NO-MOORE-NOT: moore.

// Reserve the preferred generated name to exercise symbol uniquing.
func.func private @"cg::sample"()

// CHECK-LABEL: func.func private @"cg::sample_0"(
// CHECK-SAME: %[[HANDLE:.*]]: !llvm.ptr, %[[SIGNED:.*]]: i32, %[[NARROW:.*]]: i4, %[[WIDE:.*]]: i128, %[[ENABLE:.*]]: i1)
moore.covergroup.decl @cg {
^bb0(%signed: !moore.l32, %narrow: !moore.i4, %wide: !moore.i128, %enable: !moore.i1):
  // CHECK: %[[NULL:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK: %[[IS_NULL:.*]] = llvm.icmp "eq" %[[HANDLE]], %[[NULL]]
  // CHECK: scf.if %[[IS_NULL]] {
  // CHECK: call @abort()
  // CHECK: scf.if %[[ENABLE]] {
  // CHECK: %[[SIGN:.*]] = hw.constant -2147483648 : i32
  // CHECK: %[[ORDERED:.*]] = comb.xor %[[SIGNED]], %[[SIGN]]
  // CHECK: %[[BIN:.*]] = comb.extract %[[ORDERED]] from 26 : (i32) -> i6
  // CHECK: arith.extui %[[BIN]] : i6 to i64
  // CHECK: llvm.getelementptr %[[HANDLE]]
  // CHECK: %[[COUNT:.*]] = llvm.load
  // CHECK: %[[NEXT:.*]] = arith.addi %[[COUNT]],
  // CHECK: %[[FULL:.*]] = arith.cmpi eq, %[[COUNT]],
  // CHECK: %[[UPDATED:.*]] = arith.select %[[FULL]], %[[COUNT]], %[[NEXT]]
  // CHECK: llvm.store %[[UPDATED]],
  moore.coverpoint "signed" %signed if %enable {isSigned} : l32
  // CHECK: scf.if %[[ENABLE]] {
  // CHECK: arith.extui %[[NARROW]] : i4 to i64
  // CHECK: arith.constant 64 : i64
  // CHECK: llvm.store
  moore.coverpoint "narrow" %narrow if %enable : i4
  // CHECK: scf.if %[[ENABLE]] {
  // CHECK: comb.extract %[[WIDE]] from 122 : (i128) -> i6
  // CHECK: arith.constant 128 : i64
  // CHECK: llvm.store
  moore.coverpoint "wide" %wide if %enable : i128
  // CHECK: return
}

// CHECK-LABEL: func.func @allocate() -> !llvm.ptr
func.func @allocate() -> !moore.covergroup<@cg> {
  // CHECK: %[[COUNT:.*]] = llvm.mlir.constant(192 : i64)
  // CHECK: %[[SIZE:.*]] = llvm.mlir.constant(8 : i64)
  // CHECK: %[[HANDLE:.*]] = call @calloc(%[[COUNT]], %[[SIZE]]) : (i64, i64) -> !llvm.ptr
  %handle = moore.covergroup.new : <@cg>
  // CHECK: return %[[HANDLE]] : !llvm.ptr
  return %handle : !moore.covergroup<@cg>
}

// CHECK-LABEL: func.func @sample(
// CHECK-SAME: %[[HANDLE:.*]]: !llvm.ptr,
func.func @sample(%handle: !moore.covergroup<@cg>, %signed: !moore.l32,
                  %narrow: !moore.i4, %wide: !moore.i128, %enable: !moore.i1) {
  // CHECK: call @"cg::sample_0"(
// CHECK-SAME: %[[HANDLE]],
  moore.covergroup.sample %handle(%signed, %narrow, %wide, %enable) : <@cg>(!moore.l32, !moore.i4, !moore.i128, !moore.i1)
  return
}

// CHECK-LABEL: func.func @null() -> !llvm.ptr
func.func @null() -> !moore.covergroup<@cg> {
  // CHECK: %[[NULL:.*]] = llvm.mlir.zero : !llvm.ptr
  %null = moore.covergroup.null : <@cg>
  // CHECK: return %[[NULL]] : !llvm.ptr
  return %null : !moore.covergroup<@cg>
}

// Empty groups still get distinct non-null allocations and a null sample check.
// CHECK-LABEL: func.func private @"empty::sample"(
// CHECK-SAME: %[[HANDLE:.*]]: !llvm.ptr)
// CHECK: llvm.icmp "eq" %[[HANDLE]],
// CHECK: call @abort()
moore.covergroup.decl @empty {
}

// CHECK-LABEL: func.func @test_empty()
func.func @test_empty() {
  // CHECK: %[[COUNT:.*]] = llvm.mlir.constant(1 : i64)
  // CHECK: %[[SIZE:.*]] = llvm.mlir.constant(8 : i64)
  // CHECK: %[[HANDLE:.*]] = call @calloc(%[[COUNT]], %[[SIZE]])
  %handle = moore.covergroup.new : <@empty>
  // CHECK: call @"empty::sample"(%[[HANDLE]]) : (!llvm.ptr) -> ()
  moore.covergroup.sample %handle() : <@empty>
  return
}

// Explicit bins count once per hit, including when multiple values match.
// Illegal bins raise an error only when their matching predicate is true.
// CHECK-LABEL: func.func private @"explicit::sample"(
// CHECK-SAME: %[[HANDLE:.*]]: !llvm.ptr, %[[HIT:.*]]: i1, %[[BAD:.*]]: i1)
moore.covergroup.decl @explicit {
^bb0(%hit: !moore.i1, %bad: !moore.i1):
  // CHECK: call @abort
  // CHECK: scf.if %[[HIT]] {
  // CHECK: llvm.load
  // CHECK: arith.addi
  // CHECK: arith.select
  // CHECK: llvm.store
  moore.coverbin "value" "zero" if %hit
  // CHECK: scf.if %[[BAD]] {
  // CHECK-NEXT: call @abort
  moore.coverbin "value" "one" if %bad {illegal}
  // CHECK: return
}

// CHECK-LABEL: func.func @allocate_explicit()
func.func @allocate_explicit() -> !moore.covergroup<@explicit> {
  // Only the ordinary explicit bin needs a counter.
  // CHECK: %[[COUNT:.*]] = llvm.mlir.constant(1 : i64)
  // CHECK: %[[SIZE:.*]] = llvm.mlir.constant(8 : i64)
  // CHECK: call @calloc(%[[COUNT]], %[[SIZE]])
  %instance = moore.covergroup.new : <@explicit>
  return %instance : !moore.covergroup<@explicit>
}
