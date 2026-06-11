library(MACSr)

# The vignette uses ExperimentHub to download BED files, which requires internet access.
# To ensure the script runs fully offline, we construct synthetic BED files 
# for the CHIP (treatment) and CTRL (control) inputs.

# Generate synthetic BED data for CHIP
set.seed(123)
n_chip <- 1000
chip_bed <- data.frame(
  chrom = rep("chr1", n_chip),
  chromStart = sample(10000:20000, n_chip, replace = TRUE),
  chromEnd = integer(n_chip),
  name = paste0("read_chip_", 1:n_chip),
  score = 0,
  strand = sample(c("+", "-"), n_chip, replace = TRUE)
)
chip_bed$chromEnd <- chip_bed$chromStart + 101

# Generate synthetic BED data for CTRL
n_ctrl <- 1000
ctrl_bed <- data.frame(
  chrom = rep("chr1", n_ctrl),
  chromStart = sample(10000:50000, n_ctrl, replace = TRUE),
  chromEnd = integer(n_ctrl),
  name = paste0("read_ctrl_", 1:n_ctrl),
  score = 0,
  strand = sample(c("+", "-"), n_ctrl, replace = TRUE)
)
ctrl_bed$chromEnd <- ctrl_bed$chromStart + 101

# Write the synthetic BED files to the working directory
write.table(chip_bed, file = "CHIP", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
write.table(ctrl_bed, file = "CTRL", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)