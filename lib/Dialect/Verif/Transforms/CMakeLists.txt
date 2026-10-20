add_circt_dialect_library(CIRCTVerifTransforms
  AbstractRandom.cpp
  CombineAssertLike.cpp
  FoldAssume.cpp
  LowerContracts.cpp
  LowerSymbolicValues.cpp
  LowerTests.cpp
  PrepareForFormal.cpp
  SimplifyAssumeEq.cpp
  StripContracts.cpp
  VerifyClockedAssertLike.cpp

  DEPENDS
  CIRCTVerifTransformsIncGen

  LINK_LIBS PUBLIC
  CIRCTComb
  CIRCTHW
  CIRCTLLHD
  CIRCTLTL
  CIRCTSupport
  CIRCTSV
  CIRCTVerif
  MLIRFuncDialect
  MLIRIR
  MLIRLLVMDialect
  MLIRPass
  MLIRTransforms
  MLIRTransformUtils
)
