// RUN: circt-verilog --ir-moore %s | FileCheck %s
// RUN: circt-verilog %s > /dev/null
// REQUIRES: slang
// UNSUPPORTED: valgrind

typedef struct packed {logic [3:0] upper; logic [3:0] lower;} byte_t;

module child(input logic [7:0] values [2], output logic [7:0] result);
  assign result = values[0];
endmodule

// CHECK-LABEL: moore.module @top
module top(input logic [7:0] data, output logic [7:0] result);
  byte_t values[2];
  assign values[0] = data;
  assign values[1] = data;
  child inst(.values, .result);
endmodule

// Check both array elements and opposite declared index directions to ensure
// that conversions preserve positional element order, rather than index names.
// CHECK-LABEL: moore.module @struct_to_vector
// CHECK: [[FIRST:%.+]] = moore.extract %values from 1
// CHECK: [[FIRST_BITS:%.+]] = moore.packed_to_sbv [[FIRST]]
// CHECK: [[SECOND:%.+]] = moore.extract %values from 0
// CHECK: [[SECOND_BITS:%.+]] = moore.packed_to_sbv [[SECOND]]
// CHECK: [[RESULT:%.+]] = moore.array_create [[FIRST_BITS]], [[SECOND_BITS]]
// CHECK: moore.output [[RESULT]]
module struct_to_vector(input byte_t values[3:2],
                        output logic [7:0] result[0:1]);
  assign result = values;
endmodule

// CHECK-LABEL: moore.module @vector_to_struct
// CHECK: [[FIRST:%.+]] = moore.extract %values from 1
// CHECK: [[FIRST_STRUCT:%.+]] = moore.sbv_to_packed [[FIRST]]
// CHECK: [[SECOND:%.+]] = moore.extract %values from 0
// CHECK: [[SECOND_STRUCT:%.+]] = moore.sbv_to_packed [[SECOND]]
// CHECK: [[RESULT:%.+]] = moore.array_create [[FIRST_STRUCT]], [[SECOND_STRUCT]]
// CHECK: moore.output [[RESULT]]
module vector_to_struct(input logic [7:0] values[2],
                        output byte_t result[2]);
  assign result = values;
endmodule

// CHECK-LABEL: moore.module @nested
// CHECK: [[ROW1:%.+]] = moore.extract %values from 1
// CHECK: [[EL11:%.+]] = moore.extract [[ROW1]] from 1
// CHECK: [[BITS11:%.+]] = moore.packed_to_sbv [[EL11]]
// CHECK: [[EL10:%.+]] = moore.extract [[ROW1]] from 0
// CHECK: [[BITS10:%.+]] = moore.packed_to_sbv [[EL10]]
// CHECK: [[CONV1:%.+]] = moore.array_create [[BITS11]], [[BITS10]]
// CHECK: [[ROW0:%.+]] = moore.extract %values from 0
// CHECK: [[EL01:%.+]] = moore.extract [[ROW0]] from 1
// CHECK: [[BITS01:%.+]] = moore.packed_to_sbv [[EL01]]
// CHECK: [[EL00:%.+]] = moore.extract [[ROW0]] from 0
// CHECK: [[BITS00:%.+]] = moore.packed_to_sbv [[EL00]]
// CHECK: [[CONV0:%.+]] = moore.array_create [[BITS01]], [[BITS00]]
// CHECK: [[RESULT:%.+]] = moore.array_create [[CONV1]], [[CONV0]]
// CHECK: moore.output [[RESULT]]
module nested(input byte_t values[2][2],
              output logic [7:0] result[2][2]);
  assign result = values;
endmodule
