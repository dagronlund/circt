// RUN: circt-verilog --ir-moore %s | FileCheck %s
// RUN: circt-verilog %s | FileCheck %s --check-prefix=HW
// REQUIRES: slang
// UNSUPPORTED: valgrind

// CHECK-LABEL: moore.module @top
// CHECK: [[CODE:%.+]] = moore.packed_to_sbv %{{.+}} : array<4 x l8>
// CHECK: [[STRING:%.+]] = moore.constant_string "ABCD" : i32
// CHECK: [[LABEL:%.+]] = moore.int_to_logic [[STRING]] : i32
// CHECK: moore.case_eq [[CODE]], [[LABEL]] : l32
// HW-LABEL: hw.module @top
// HW-NOT: llhd.
// HW: [[CONST:%.+]] = hw.constant 1094861636 : i32
// HW: [[BITS:%.+]] = hw.bitcast %code : (!hw.array<4xi8>) -> i32
// HW: [[MATCH:%.+]] = comb.icmp ceq [[BITS]], [[CONST]] : i32
// HW-NOT: llhd.
// HW: hw.output [[MATCH]] : i1
module top(input logic [3:0][7:0] code, output logic matched);
  always_comb begin
    case (code)
      "ABCD": matched = '1;
      default: matched = '0;
    endcase
  end
endmodule

// Normalize aggregate case items as well as the selector. Keep wildcard
// comparison semantics when converting the packed representations.
// CHECK-LABEL: moore.module @wildcard_x
// CHECK: [[CODE:%.+]] = moore.packed_to_sbv %{{.+}} : array<2 x l4>
// CHECK: [[PATTERN:%.+]] = moore.packed_to_sbv %{{.+}} : array<2 x l4>
// CHECK: moore.casexz_eq [[CODE]], [[PATTERN]] : l8
// HW-LABEL: hw.module @wildcard_x
// HW: hw.output
module wildcard_x(input logic [1:0][3:0] code, pattern, output logic matched);
  always_comb begin
    casex (code)
      pattern: matched = 1;
      default: matched = 0;
    endcase
  end
endmodule

// CHECK-LABEL: moore.module @wildcard_z
// CHECK: [[CODE:%.+]] = moore.packed_to_sbv %{{.+}} : array<2 x l4>
// CHECK: [[PATTERN:%.+]] = moore.packed_to_sbv %{{.+}} : array<2 x l4>
// CHECK: moore.casez_eq [[CODE]], [[PATTERN]] : l8
// HW-LABEL: hw.module @wildcard_z
// HW: hw.output
module wildcard_z(input logic [1:0][3:0] code, pattern, output logic matched);
  always_comb begin
    casez (code)
      pattern: matched = 1;
      default: matched = 0;
    endcase
  end
endmodule

typedef struct packed {logic [3:0] upper; logic [3:0] lower;} byte_t;
// CHECK-LABEL: moore.module @struct_item
// CHECK: [[PATTERN:%.+]] = moore.packed_to_sbv %{{.+}} : struct<{{.*}}>
// CHECK: moore.case_eq %{{.+}}, [[PATTERN]] : l8
// HW-LABEL: hw.module @struct_item
// HW: hw.output
module struct_item(input logic [7:0] code, input byte_t pattern,
                   output logic matched);
  always_comb begin
    case (code)
      pattern: matched = 1;
      default: matched = 0;
    endcase
  end
endmodule
