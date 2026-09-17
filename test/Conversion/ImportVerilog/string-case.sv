// RUN: circt-verilog --ir-moore %s | FileCheck %s
// RUN: circt-verilog %s | FileCheck %s --check-prefix=CORE
// REQUIRES: slang
// UNSUPPORTED: valgrind

// CHECK-LABEL: moore.module @top
// CHECK: [[TOKEN:%.+]] = moore.read %token{{.*}} : <string>
// CHECK: [[BYTES:%.+]] = moore.constant_string "hello" : i40
// CHECK: [[LABEL:%.+]] = moore.int_to_string [[BYTES]] : i40
// CHECK: [[EQ:%.+]] = moore.string_cmp eq [[TOKEN]], [[LABEL]] : string -> i1
// CHECK: [[COND:%.+]] = moore.to_builtin_int [[EQ]] : i1
// CHECK: cf.cond_br [[COND]], ^[[MATCH:bb[0-9]+]], ^[[DEFAULT:bb[0-9]+]]
// CHECK: ^[[MATCH]]:
// CHECK: moore.blocking_assign %matched, %{{.+}} : l1
// CHECK: ^[[DEFAULT]]:
// CHECK: moore.blocking_assign %matched, %{{.+}} : l1
// CORE-LABEL: hw.module @top
// CORE: sim.string.cmp eq
module top(input string token, output logic matched);
  always_comb begin
    case (token)
      "hello": matched = 1'b1;
      default: matched = 1'b0;
    endcase
  end
endmodule

// Variable labels and multiple labels in one item use string equality too.
// CHECK-LABEL: moore.module @variable_labels
// CHECK: [[TOKEN:%.+]] = moore.read %token{{.*}} : <string>
// CHECK: [[PATTERN:%.+]] = moore.read %pattern{{.*}} : <string>
// CHECK: moore.string_cmp eq [[TOKEN]], [[PATTERN]] : string -> i1
// CHECK: cf.cond_br %{{.+}}, ^[[MATCH:bb[0-9]+]], ^{{bb[0-9]+}}
// CHECK: [[EMPTY:%.+]] = moore.constant_string "" : i8
// CHECK: [[LABEL:%.+]] = moore.int_to_string [[EMPTY]] : i8
// CHECK: moore.string_cmp eq [[TOKEN]], [[LABEL]] : string -> i1
// CHECK: cf.cond_br %{{.+}}, ^[[MATCH]], ^{{bb[0-9]+}}
// CORE-LABEL: hw.module @variable_labels
// CORE: sim.string.cmp eq
// CORE: sim.string.cmp eq
module variable_labels(input string token, pattern, output logic matched);
  always_comb begin
    case (token)
      pattern, "": matched = 1'b1;
      default: matched = 1'b0;
    endcase
  end
endmodule
