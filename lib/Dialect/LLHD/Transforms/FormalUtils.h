//===- FormalUtils.h - Formal LLHD lowering utilities -----------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef CIRCT_DIALECT_LLHD_TRANSFORMS_FORMALUTILS_H
#define CIRCT_DIALECT_LLHD_TRANSFORMS_FORMALUTILS_H

#include "circt/Dialect/LLHD/LLHDOps.h"
#include "circt/Dialect/Verif/VerifOps.h"

namespace circt::llhd {
inline bool isFormalCheck(mlir::Operation *op) {
  return mlir::isa<verif::AssertOp, verif::AssumeOp, verif::CoverOp,
                   verif::ClockedAssertOp, verif::ClockedAssumeOp,
                   verif::ClockedCoverOp>(op);
}
inline bool isClockedFormalCheck(mlir::Operation *op) {
  return mlir::isa<verif::ClockedAssertOp, verif::ClockedAssumeOp,
                   verif::ClockedCoverOp>(op);
}
/// These utilities deliberately do not change the simulation passes' defaults.
void removeFormalControlFlow(CombinationalOp op);
mlir::LogicalResult deseqFormal(ProcessOp op);
void hoistFormalSignals(mlir::Operation *op);
void unrollFormalLoops(mlir::Operation *op);
/// Constrain state to an input-dependent startup value until its first edge.
void constrainFormalInitialState(mlir::OpBuilder &builder, mlir::Location loc,
                                 mlir::Value state, mlir::Value clock,
                                 mlir::Value initial, mlir::Value reset = {});
} // namespace circt::llhd

#endif // CIRCT_DIALECT_LLHD_TRANSFORMS_FORMALUTILS_H
