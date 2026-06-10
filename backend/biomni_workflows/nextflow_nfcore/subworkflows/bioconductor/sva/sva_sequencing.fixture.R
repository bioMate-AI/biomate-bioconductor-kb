# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("sva", "zebrafishRNASeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(sva)
library(zebrafishRNASeq)

# Reproduce the vignette's data preparation
data(zfGenes)
filter = apply(zfGenes, 1, function(x) length(x[x>5])>=2)
filtered = zfGenes[filter,]
genes = rownames(filtered)[grep("^ENS", rownames(filtered))]
controls = grepl("^ERCC", rownames(filtered))
group = as.factor(rep(c("Ctl", "Trt"), each=3))
dat0 = as.matrix(filtered)

# Create sample metadata based on the vignette's group variable
sample_metadata = data.frame(
    sample_id = colnames(dat0),
    group = group,
    stringsAsFactors = FALSE
)

# Serialize to the expected input files
write.csv(dat0, "raw_counts.csv", quote = FALSE)
write.csv(sample_metadata, "sample_metadata.csv", row.names = FALSE, quote = FALSE)