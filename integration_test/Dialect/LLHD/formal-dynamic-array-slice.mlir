// REQUIRES: slang, verilator
// RUN: circt-verilog --ir-hw %CIRCT_SOURCE%/test/circt-verilog/formal-dynamic-array-slice.sv | circt-opt --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-opt %t.formal.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.model %t.sv %S/Inputs/dynamic-array-slice-driver.cpp > %t.build.log 2>&1
// RUN: %t.model/Vtop | FileCheck %s --check-prefix=CHECK
// RUN: circt-opt %t.formal.mlir --comb-assume-two-valued --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.two-valued.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.two-valued.model %t.two-valued.sv %S/Inputs/dynamic-array-slice-driver.cpp > %t.two-valued.build.log 2>&1
// RUN: %t.two-valued.model/Vtop | FileCheck %s --check-prefix=CHECK
// RUN: circt-verilog --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-dynamic-array-slice.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/dynamic-array-slice-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s --check-prefix=CHECK
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --prefix Vtop --top-module multiple_slices -CFLAGS -DSECOND_SLICE --Mdir %t.multiple.model %t.sv %S/Inputs/dynamic-array-slice-driver.cpp > %t.multiple.build.log 2>&1
// RUN: %t.multiple.model/Vtop | FileCheck %s --check-prefix=CHECK
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --prefix Vtop --top-module multiple_slices -CFLAGS -DSECOND_SLICE --Mdir %t.multiple.direct.model %t.direct.sv %S/Inputs/dynamic-array-slice-driver.cpp > %t.multiple.direct.build.log 2>&1
// RUN: %t.multiple.direct.model/Vtop | FileCheck %s --check-prefix=CHECK
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --prefix Vtop --top-module ascending -CFLAGS -DASCENDING --Mdir %t.ascending.model %t.sv %S/Inputs/dynamic-array-slice-driver.cpp > %t.ascending.build.log 2>&1
// RUN: %t.ascending.model/Vtop | FileCheck %s --check-prefix=CHECK
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --prefix Vtop --top-module small_array -CFLAGS -DSMALL_ARRAY --Mdir %t.small.model %t.sv %S/Inputs/dynamic-array-slice-driver.cpp > %t.small.build.log 2>&1
// RUN: %t.small.model/Vtop | FileCheck %s --check-prefix=SMALL
// CHECK: 262144 dynamic array slice transitions and synchronous timing checks passed
// SMALL: 512 dynamic array slice transitions and synchronous timing checks passed
module {}
