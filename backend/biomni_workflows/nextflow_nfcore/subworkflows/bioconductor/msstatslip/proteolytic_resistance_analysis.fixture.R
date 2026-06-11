# Load required libraries
library(data.table)

# 1. Create synthetic Spectronaut export for LiP data (raw_lip)
# The vignette replaces "P37840.1" with "P37840", so we use "P37840.1" as the protein name.
# Conditions for LiP in the vignette are F1 and M1.
runs_lip <- paste0("run", 1:8)
conditions_lip <- rep(c("F1", "M1"), each=4)
bioreps_lip <- rep(1:4, 2)

base_lip <- data.frame(
  PG.ProteinGroups = "P37840.1",
  PG.ProteinAccessions = "P37840.1",
  PEP.StrippedSequence = "QGVAEAAGK",
  EG.ModifiedSequence = "QGVAEAAGK",
  FG.Charge = 2,
  F.FrgIon = "y4",
  F.Charge = 1,
  R.Condition = conditions_lip,
  R.Replicate = bioreps_lip,
  R.FileName = runs_lip,
  F.PeakArea = 2000,
  F.ExcludedFromQuantification = FALSE,
  EG.Qvalue = 0.001,
  stringsAsFactors = FALSE
)

# Add multiple fragments and peptides to ensure features pass the >= 3 measurements filter
df2_lip <- base_lip
df2_lip$F.FrgIon <- "y5"

df3_lip <- base_lip
df3_lip$PEP.StrippedSequence <- "EGVVHGVATVAEK"
df3_lip$EG.ModifiedSequence <- "EGVVHGVATVAEK"

df4_lip <- df3_lip
df4_lip$F.FrgIon <- "y5"

raw_lip <- rbind(base_lip, df2_lip, df3_lip, df4_lip)

# 2. Create synthetic Spectronaut export for TrP data (raw_prot)
# The vignette maps LiP F1 -> TrP F2, and LiP M1 -> TrP M2.
runs_prot <- paste0("run", 9:16)
conditions_prot <- rep(c("F2", "M2"), each=4)

raw_prot <- raw