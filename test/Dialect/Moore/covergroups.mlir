// RUN: circt-opt --verify-roundtrip %s | FileCheck %s
// RUN: circt-opt --canonicalize %s | FileCheck %s

// CHECK-LABEL: moore.covergroup.decl @cg
moore.covergroup.decl @cg {
^bb0(%value: !moore.l32):
  %enabled = moore.constant 1 : i1
  // CHECK: moore.coverpoint "value"
  moore.coverpoint "value" %value if %enabled {isSigned} : l32
}

func.func @sample() {
  // CHECK: moore.covergroup.new
  %instance = moore.covergroup.new : !moore.covergroup<@cg>
  %one = moore.constant 1 : l32
  // CHECK: moore.covergroup.sample
  moore.covergroup.sample %instance(%one) : !moore.covergroup<@cg>(!moore.l32)
  // CHECK: moore.covergroup.sample
  moore.covergroup.sample %instance(%one) : !moore.covergroup<@cg>(!moore.l32)
  return
}

func.func @null() -> !moore.covergroup<@cg> {
  %null = moore.covergroup.null : !moore.covergroup<@cg>
  return %null : !moore.covergroup<@cg>
}
