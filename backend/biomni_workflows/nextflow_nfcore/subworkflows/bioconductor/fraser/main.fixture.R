# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("FRASER", "data.table")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(FRASER)
library(data.table)

# Read the original sampleTable provided by the FRASER package
orig_sampleTable_path <- system.file("extdata", "sampleTable.tsv", package="FRASER", mustWork=TRUE)
sampleTable <- fread(orig_sampleTable_path)

# Resolve the absolute paths to the original BAM files shipped with the package
orig_bamFiles <- unname(sapply(sampleTable$bamFile, function(x) {
    system.file(x, package="FRASER", mustWork=TRUE)
}))

# Define local filenames for the BAM files
local_bamFiles <- basename(orig_bamFiles)

# Copy BAM files and their indices to the current working directory
for (i in seq_along(orig_bamFiles)) {
    file.copy(orig_bamFiles[i], local_bamFiles[i], overwrite = TRUE)
    
    # Check for and copy corresponding BAM index files (.bam.bai or .bai)
    bai_file1 <- paste0(orig_bamFiles[i], ".bai")
    bai_file2 <- sub("\\.bam$", ".bai", orig_bamFiles[i])
    
    if (file.exists(bai_file1)) {
        file.copy(bai_file1, paste0(local_bamFiles[i], ".bai"), overwrite = TRUE)
    }
    if (file.exists(bai_file2)) {
        file.copy(bai_file2, sub("\\.bam$", ".bai", local_bamFiles[i]), overwrite = TRUE)
    }
}

# Update the sampleTable to point to the local BAM files in the working directory
sampleTable[, bamFile := local_bamFiles]

# Write the updated sample annotation table to the working directory
fwrite(sampleTable, "sampleTable.tsv", sep="\t", quote=FALSE)