// RUN: circt-opt %s --verif-abstract-random --split-input-file --verify-diagnostics

func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i16
hw.module @signature(out value: i16) {
  %zero = hw.constant 0 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  // expected-error @+1 {{expected an external __circt_urandom_range call with type (i32, i32, !llvm.ptr) -> i32}}
  %draw = func.call @__circt_urandom_range(%zero, %zero, %null) : (i32, i32, !llvm.ptr) -> i16
  hw.output %draw : i16
}

// -----

func.func @__circt_urandom_range(%low: i32, %high: i32, %seed: !llvm.ptr) -> i32 {
  return %low : i32
}
hw.module @defined_helper(out value: i32) {
  %zero = hw.constant 0 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  // expected-error @+1 {{expected an external __circt_urandom_range call}}
  %draw = func.call @__circt_urandom_range(%zero, %zero, %null) : (i32, i32, !llvm.ptr) -> i32
  hw.output %draw : i32
}

// -----

func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
func.func private @observe(!llvm.ptr)
hw.module @escaping_seed(out value: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %one = hw.constant 1 : i32
  %value = llhd.combinational -> i32 {
    %tmp = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
    llvm.store %zero, %tmp : i32, !llvm.ptr
    // expected-error @+1 {{unsupported random seed storage}}
    %draw = func.call @__circt_urandom_range(%zero, %max, %tmp) : (i32, i32, !llvm.ptr) -> i32
    %next = llvm.load %tmp : !llvm.ptr -> i32
    func.call @observe(%tmp) : (!llvm.ptr) -> ()
    llhd.yield %draw : i32
  }
  hw.output %value : i32
}

// -----

func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
hw.module @loop(in %again: i1, out value: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %value = llhd.combinational -> i32 {
    cf.br ^body
  ^body:
    // expected-error @+1 {{random call may execute repeatedly without an LLHD suspension}}
    %draw = func.call @__circt_urandom_range(%zero, %max, %null) : (i32, i32, !llvm.ptr) -> i32
    cf.cond_br %again, ^body, ^exit
  ^exit:
    llhd.yield %draw : i32
  }
  hw.output %value : i32
}

// -----

func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
func.func @uninlined(%low: i32, %high: i32, %seed: !llvm.ptr) -> i32 {
  // expected-error @+1 {{random call must be directly nested in an HW module or LLHD procedural region}}
  %draw = func.call @__circt_urandom_range(%low, %high, %seed) : (i32, i32, !llvm.ptr) -> i32
  return %draw : i32
}

// -----

func.func private @__circt_urandom_range(i32, i32, !llvm.ptr) -> i32
hw.module @structured(in %condition: i1, out value: i32) {
  %zero = hw.constant 0 : i32
  %max = hw.constant -1 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %value = llhd.combinational -> i32 {
    %value = scf.if %condition -> i32 {
      // expected-error @+1 {{random call must be directly nested in an HW module or LLHD procedural region}}
      %draw = func.call @__circt_urandom_range(%zero, %max, %null) : (i32, i32, !llvm.ptr) -> i32
      scf.yield %draw : i32
    } else {
      scf.yield %zero : i32
    }
    llhd.yield %value : i32
  }
  hw.output %value : i32
}
