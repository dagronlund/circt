// RUN: circt-opt %s --verif-abstract-random | %PYTHON% %S/Inputs/abstract-random-ranges.py
// RUN: circt-opt %s --comb-assume-two-valued --verif-abstract-random | %PYTHON% %S/Inputs/abstract-random-ranges.py
// RUN: circt-opt %s --verif-abstract-random='assume-ranges=false' | %PYTHON% %S/Inputs/abstract-random-ranges.py --unbounded

func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
hw.module @ranges(in %low: i32, in %high: i32, out dynamic: i32, out ordered: i32, out reversed: i32, out singleton: i32, out zero: i32, out unsigned_high: i32, out full: i32, out default_min: i32) {
  %null = llvm.mlir.zero : !llvm.ptr
  %zero = hw.constant 0 : i32
  %three = hw.constant 3 : i32
  %seven = hw.constant 7 : i32
  %ten = hw.constant 10 : i32
  %negative = hw.constant -2147483648 : i32
  %max = hw.constant -1 : i32
  %dynamic = func.call @__circt_urandom_range(%low, %high, %null) : (i32, i32, !llvm.ptr) -> i32
  %ordered = func.call @__circt_urandom_range(%three, %ten, %null) : (i32, i32, !llvm.ptr) -> i32
  %reversed = func.call @__circt_urandom_range(%ten, %three, %null) : (i32, i32, !llvm.ptr) -> i32
  %singleton = func.call @__circt_urandom_range(%seven, %seven, %null) : (i32, i32, !llvm.ptr) -> i32
  %single_zero = func.call @__circt_urandom_range(%zero, %zero, %null) : (i32, i32, !llvm.ptr) -> i32
  %unsigned_high = func.call @__circt_urandom_range(%negative, %max, %null) : (i32, i32, !llvm.ptr) -> i32
  %full = func.call @__circt_urandom_range(%zero, %max, %null) : (i32, i32, !llvm.ptr) -> i32
  %default_min = func.call @__circt_urandom_range(%zero, %ten, %null) : (i32, i32, !llvm.ptr) -> i32
  hw.output %dynamic, %ordered, %reversed, %singleton, %single_zero, %unsigned_high, %full, %default_min : i32, i32, i32, i32, i32, i32, i32, i32
}
