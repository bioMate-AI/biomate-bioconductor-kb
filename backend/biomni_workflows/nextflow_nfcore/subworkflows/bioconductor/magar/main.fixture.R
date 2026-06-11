library(MAGAR)
library(RnBeads)

# 1. Load the bundled methQTLInput object to extract a valid RnBSet
imp.data <- loadMethQTLInput(system.file("extdata", "reduced_methQTL", package = "MAGAR"))
rnb.set <- meth.data(imp.data)

# 2. Save the RnBSet to 'rnb_set_dir'
if (dir.exists("rnb_set_dir")) {
    unlink("rnb_set_dir", recursive = TRUE)
}
save.rnb.set(rnb.set, path = "rnb_set_dir", archive = FALSE)

# Extract sample IDs to ensure consistency across all inputs
sample_ids <- samples(rnb.set)
n_samples <- length(sample_ids)

# 3. Create PLINK data files in 'plink_data' directory
dir.create("plink_data", showWarnings = FALSE)

# .fam file
fam_data <- data.frame(
  FID = paste0("FAM", seq_len(n_samples)),
  IID = sample_ids,
  PID = rep(0, n_samples),
  MID = rep(0, n_samples),
  Sex = rep(1, n_samples),
  Pheno = rep(1, n_samples)
)
write.table(fam_data, "plink_data/data.fam", row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")

# .bim file
bim_data <- data.frame(
  CHR = c(1, 1),
  SNP = c("SNP1", "SNP2"),
  CM = c(0, 0),
  BP = c(1000, 2000),
  A1 = c("A", "C"),
  A2 = c("G", "T")
)
write.table(bim_data, "plink_data/data.bim", row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")

# .bed file (binary)
n_bytes <- ceiling(n_samples / 4)
bed_file <- file("plink_data/data.bed", "wb")
# PLINK magic number
writeBin(as.raw(c(0x6c, 0x1b, 0x01)), bed_file)
# Genotype data: 0x00 means homozygous for A1 for all samples
for (i in 1:2) {
  writeBin(rep(as.raw(0x00), n_bytes), bed_file)
}
close(bed_file)

# 4. Create sample_annotation.csv
anno_data <- data.frame(
  SampleID = sample_ids,
  age = sample(20:60, n_samples, replace = TRUE),
  sex = sample(c("f", "m"), n_samples, replace = TRUE),
  barcode = paste0("209054857842_R0", seq_len(n_samples), "C01")
)
write.csv(anno_data, "sample_annotation.csv", row.names = FALSE, quote = FALSE)

# Verify all required files exist
stopifnot(
  dir.exists("rnb_set_dir"),
  dir.exists("plink_data"),
  file.exists("plink_data/data.bed"),
  file.exists("plink_data/data.bim"),
  file.exists("plink_data/data.fam"),
  file.exists("sample_annotation.csv")
)