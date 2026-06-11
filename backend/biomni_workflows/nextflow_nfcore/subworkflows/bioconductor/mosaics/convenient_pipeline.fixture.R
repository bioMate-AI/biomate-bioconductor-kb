library(mosaics)

set.seed(123)

# Generate synthetic eland_result for ChIP
chip_eland <- data.frame(
  V1 = paste0("read_chip_", 1:1000),
  V2 = rep("ACGTACGTACGTACGT", 1000),
  V3 = rep("U0", 1000),
  V4 = rep(1, 1000),
  V5 = rep(0, 1000),
  V6 = rep(0, 1000),
  V7 = rep("chr22", 1000),
  V8 = sample(16000000:16050000, 1000, replace=TRUE),
  V9 = sample(c("F", "R"), 1000, replace=TRUE),
  stringsAsFactors = FALSE
)

# Generate synthetic eland_result for Control
control_eland <- data.frame(
  V1 = paste0("read_ctrl_", 1:1000),
  V2 = rep("ACGTACGTACGTACGT", 1000),
  V3 = rep("U0", 1000),
  V4 = rep(1, 1000),
  V5 = rep(0, 1000),
  V6 = rep(0, 1000),
  V7 = rep("chr22", 1000),
  V8 = sample(16000000:16050000, 1000, replace=TRUE),
  V9 = sample(c("F", "R"), 1000, replace=TRUE),
  stringsAsFactors = FALSE
)

# Write to the expected input files
write.table(chip_eland, "STAT1_ChIP_eland_results.txt", sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE)
write.table(control_eland, "STAT1_control_eland_results.txt", sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE)