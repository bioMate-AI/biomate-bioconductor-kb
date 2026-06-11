library(GeneRegionScan)

# Load example data from the package as demonstrated in the vignette
data(exampleProbeLevelSet)

# 1. Construct synthetic Transcript Clusters File
transcript_csv <- data.frame(
  probeset_id = c("1234567", "1234568"),
  seqname = c("chr2", "chr2"),
  strand = c("+", "+"),
  start = c(215889955, 215890000),
  stop = c(215889999, 215890100)
)
write.csv(transcript_csv, "~/HuEx-1-0-st-v2.na26.hg18.transcript.csv", row.names=FALSE, quote=FALSE)

# 2. Construct synthetic MPS (metaprobeset to probeset mapping) File
mps_data <- data.frame(
  probeset_id = c("1234567", "1234568"),
  transcript_cluster_id = c("1234567", "1234568"),
  probeset_list = c("2345678 2345679", "2345680")
)
write.table(mps_data, "~/HuEx-1-0-st-v2.r2.dt1.hg18.full.mps", sep="\t", row.names=FALSE, quote=FALSE)

# 3. Create CEL files directory and synthetic CEL files
dir.create("~/test-cels", showWarnings=FALSE, recursive=TRUE)
cat("[CEL]\nVersion=3\n", file="~/test-cels/test1.CEL")
cat("[CEL]\nVersion=3\n", file="~/test-cels/test2.CEL")

# 4. Construct synthetic CLF (Cell Layout) File
cat("header0=val0\n[header]\nx\ty\tprobe_id\n1\t1\t1001\n", file="~/HuEx-1-0-st-v2.r2.clf")

# 5. Construct synthetic PGF (Probe Group) File
cat("#%header0=val0\nprobeset_id\ttype\tprobe_id\tsequence\n2345678\tmain\t1001\tACGT\n", file="~/HuEx-1-0-st-v2.r2.pgf")