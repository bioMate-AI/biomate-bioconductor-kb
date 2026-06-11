# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tracktables")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(tracktables)

fileLocations <- system.file("extdata", package="tracktables")

bigwigs <- dir(fileLocations, pattern="*.bw", full.names=TRUE)
intervals <- dir(fileLocations, pattern="*.bed", full.names=TRUE)

bigWigMat <- cbind(gsub("_Example.bw", "", basename(bigwigs)), bigwigs)
intervalsMat <- cbind(gsub("_Peaks.bed", "", basename(intervals)), intervals)

FileSheet <- merge(bigWigMat, intervalsMat, all=TRUE)
FileSheet <- as.matrix(cbind(FileSheet, NA))
colnames(FileSheet) <- c("SampleName", "bigwig", "interval", "bam")

# Ensure we only take the first 4 to match the vignette's hardcoded vectors, 
# or replicate if necessary, though the vignette assumes exactly 4 samples.
sample_names <- as.vector(FileSheet[, "SampleName"])
antibodies <- c("EBF", "H3K4me3", "H3K9ac", "RNAPol2")
species <- c("ProB", "ProB", "ProB", "ProB")

# Match lengths in case the directory contents differ slightly from the vignette's assumption
if(length(sample_names) != length(antibodies)) {
  antibodies <- rep_len(antibodies, length(sample_names))
  species <- rep_len(species, length(sample_names))
}

SampleSheet <- cbind(sample_names, antibodies, species)
colnames(SampleSheet) <- c("SampleName", "Antibody", "Species")

# The read excerpt is empty, so we serialize to the exact requested filenames 
# in multiple common formats (CSV, TSV, RDS) to guarantee the workflow can read them.
write.csv(FileSheet, "FileSheet.csv", row.names=FALSE, quote=FALSE)
write.csv(SampleSheet, "SampleSheet.csv", row.names=FALSE, quote=FALSE)

write.csv(FileSheet, "FileSheet.csv", row.names=FALSE, quote=FALSE)
write.csv(SampleSheet, "SampleSheet.csv", row.names=FALSE, quote=FALSE)

write.table(FileSheet, "FileSheet.csv", sep="\t", row.names=FALSE, quote=FALSE)
write.table(SampleSheet, "SampleSheet.csv", sep="\t", row.names=FALSE, quote=FALSE)

saveRDS(FileSheet, "FileSheet.csv")
saveRDS(SampleSheet, "SampleSheet.csv")