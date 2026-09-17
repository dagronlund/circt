// RUN: circt-verilog --import-only --top=top %s | FileCheck %s
// RUN: circt-verilog --import-only --top=top %s | circt-opt --convert-moore-to-core --canonicalize | FileCheck %s --check-prefix=CORE
// REQUIRES: slang
// UNSUPPORTED: valgrind

// CHECK-LABEL: moore.module @top
// CHECK: [[BITS:%.*]] = moore.packed_to_sbv %{{.*}} : array<16 x i8>
// CHECK-NEXT: [[STR:%.*]] = moore.int_to_string [[BITS]] : i128
// CHECK-NEXT: moore.assign %{{.*}}, [[STR]] : string
// CORE-LABEL: hw.module @top
// CORE: [[BITS:%.*]] = hw.bitcast %{{.*}} : (!hw.array<16xi8>) -> i128
// CORE-NEXT: [[STR:%.*]] = sim.string.int_to_string [[BITS]] : i128
// CORE-NEXT: llhd.drv %{{.*}}, [[STR]] after %{{.*}} : !sim.dstring
module top(input bit [15:0][7:0] data, output string result);
  assign result = string'(data);
endmodule

// Four-state values are flattened before conversion to two-state bits.
// CHECK-LABEL: func.func private @cast_logic(
// CHECK: [[BITS:%.*]] = moore.packed_to_sbv %arg0 : array<16 x l8>
// CHECK-NEXT: [[INT:%.*]] = moore.logic_to_int [[BITS]] : l128
// CHECK-NEXT: [[STR:%.*]] = moore.int_to_string [[INT]] : i128
// CHECK-NEXT: return [[STR]] : !moore.string
// CORE-LABEL: func.func private @cast_logic(
// CORE: [[BITS:%.*]] = hw.bitcast %arg0 : (!hw.array<16xi8>) -> i128
// CORE-NEXT: [[STR:%.*]] = sim.string.int_to_string [[BITS]] : i128
// CORE-NEXT: return [[STR]] : !sim.dstring
function automatic string cast_logic(logic [15:0][7:0] data);
  return string'(data);
endfunction

// Nested arrays with ascending ranges retain their complete packed width.
// CHECK-LABEL: func.func private @cast_nested(
// CHECK: [[BITS:%.*]] = moore.packed_to_sbv %arg0 : array<2 x array<4 x i8>>
// CHECK-NEXT: [[STR:%.*]] = moore.int_to_string [[BITS]] : i64
// CHECK-NEXT: return [[STR]] : !moore.string
// CORE-LABEL: func.func private @cast_nested(
// CORE: [[BITS:%.*]] = hw.bitcast %arg0 : (!hw.array<2xarray<4xi8>>) -> i64
// CORE-NEXT: [[STR:%.*]] = sim.string.int_to_string [[BITS]] : i64
// CORE-NEXT: return [[STR]] : !sim.dstring
function automatic string cast_nested(bit [0:1][0:3][7:0] data);
  return string'(data);
endfunction

// Packed structs use the same conversion path.
typedef struct packed { bit [7:0] first; bit [7:0] second; } pair_t;
// CHECK-LABEL: func.func private @cast_struct(
// CHECK: [[BITS:%.*]] = moore.packed_to_sbv %arg0 : struct<{first: i8, second: i8}>
// CHECK-NEXT: [[STR:%.*]] = moore.int_to_string [[BITS]] : i16
// CHECK-NEXT: return [[STR]] : !moore.string
// CORE-LABEL: func.func private @cast_struct(
// CORE: [[BITS:%.*]] = hw.bitcast %arg0 : (!hw.struct<first: i8, second: i8>) -> i16
// CORE-NEXT: [[STR:%.*]] = sim.string.int_to_string [[BITS]] : i16
// CORE-NEXT: return [[STR]] : !sim.dstring
function automatic string cast_struct(pair_t data);
  return string'(data);
endfunction
