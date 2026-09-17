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

// CHECK-LABEL: moore.covergroup.decl @explicit
moore.covergroup.decl @explicit {
^bb0(%hit: !moore.i1):
  // CHECK: moore.coverbin "value" "zero" if
  moore.coverbin "value" "zero" if %hit
  // CHECK: moore.coverbin "value" "one" if {{.*}} {illegal}
  moore.coverbin "value" "one" if %hit {illegal}
  // Different coverpoints may reuse a bin name.
  // CHECK: moore.coverbin "other" "zero" if
  moore.coverbin "other" "zero" if %hit
}
