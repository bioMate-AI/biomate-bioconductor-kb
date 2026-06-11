suppressPackageStartupMessages({
    library(prebs)
    library(prebsdata)
    library(hgu133plus2probe)
    library(hgu133plus2cdf)
    library(affy)
})

# 1. Generate probes data as per vignette
probes <- as.data.frame(hgu133plus2probe)
probes <- probes[substr(probes$Probe.Set.Name, 1, 4) != "AFFX", ]
# Subset to keep the file size small for the test fixture
probes <- head(probes, 100)
probes$Probe.ID <- xy2indices(probes$x, probes$y, cdf="hgu133plus2cdf")

# Write to probes.txt as expected by the read.table call in the workflow
write.table(probes, file="probes.txt", quote=FALSE, row.names=FALSE, col.names=TRUE)

# Also write to "hgu133plus2probe" to satisfy the declared input file list
write.table(probes, file="hgu133plus2probe", quote=FALSE, row.names=FALSE, col.names=TRUE)

# 2. Generate output_probe_mappings.map
# The vignette expects 7 columns: "Probe.ID", "strand", "chr", "start", "seq", "match", "multiple"
# It is read with read.table() without headers.
probe_mappings <- data.frame(
    V1 = probes$Probe.ID,
    V2 = "+",
    V3 = "chr1",
    V4 = seq_len(nrow(probes)) * 100,
    V5 = probes$sequence,
    V6 = "25M",
    V7 = 1
)

write.table(probe_mappings, file="output_probe_mappings.map", quote=FALSE, row.names=FALSE, col.names=FALSE, sep="\t")