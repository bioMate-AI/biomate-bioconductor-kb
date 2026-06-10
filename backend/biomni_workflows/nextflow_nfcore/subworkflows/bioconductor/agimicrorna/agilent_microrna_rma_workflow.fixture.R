library("AgiMicroRna")

# 1. Load the targets.micro dataset from the package
data(targets.micro, package = "AgiMicroRna")

# 2. Write the targets.txt file expected by the workflow
write.table(targets.micro, file = "targets.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# 3. Construct synthetic Agilent Feature Extraction (AFE) data files
# readMicroRnaAFE wraps limma::read.maimages(..., source="agilent")
# It expects specific columns to extract signals and flags.
afe_lines <- c(
  "TYPE\tFEPARAMS",
  "FEATURES\tFeatureNum\tRow\tCol\tProbeName\tGeneName\tSystematicName\tControlType\tgTotalGeneSignal\tgMeanSignal\tgProcessedSignal\tgBGMedianSignal\tgBGUsed\tgIsGeneDetected\tgIsSaturated\tgIsFeatNonUnifOL\tgIsFeatPopnOL",
  "DATA\t1\t1\t1\thsa-miR-1\thsa-miR-1\thsa-miR-1\t0\t1000\t100\t100\t10\t10\t1\t0\t0\t0",
  "DATA\t2\t1\t2\thsa-miR-2\thsa-miR-2\thsa-miR-2\t0\t2000\t200\t200\t10\t10\t1\t0\t0\t0",
  "DATA\t3\t1\t3\tdarkcorner\tdarkcorner\tdarkcorner\t1\t50\t5\t5\t10\t10\t0\t0\t0\t0"
)

# Write the synthetic AFE files for each file named in targets.txt
for (f in targets.micro$FileName) {
  writeLines(afe_lines, con = f)
}