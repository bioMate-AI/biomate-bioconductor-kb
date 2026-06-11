# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("appreci8R")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(appreci8R)

# 1. Reproduce the 'target' data.frame from the vignette
target <- data.frame(chr = c("2","4","12","17","21","X"),
                   start = c(25469500,106196950,12046280,7579470,36164400,15838363),
                   end = c(25469510,106196960,12046350,7579475,36164410,15838366))

# 2. Serialize 'target' to a file named 'target' in the working directory.
#    The vignette describes it as "bed-format", so a tab-separated file without
#    headers or row names is appropriate.
write.table(target, file = "target.bed", sep = "\t",
            row.names = FALSE, col.names = FALSE, quote = FALSE)

# 3. Identify the source directory for example data within the appreci8R package
extdata_dir <- system.file("extdata", package = "appreci8R")

# 4. Define the input files to be copied from the package's extdata directory
#    to the current working directory. These include VCF, BAM, and BAI files.
input_files_to_copy <- c(
  "Sample1.rawMutations.vcf",
  "Sample2.rawMutations.vcf",
  "Sample1.bam",
  "Sample1.bai",
  "Sample2.bam",
  "Sample2.bai"
)

# 5. Copy each required input file to the current working directory
for (file_name in input_files_to_copy) {
  source_path <- file.path(extdata_dir, file_name)
  destination_path <- file.path(".", file_name) # Current working directory
  
  if (file.exists(source_path)) {
    file.copy(from = source_path, to = destination_path, overwrite = TRUE)
  } else {
    stop(paste("Error: Source file not found in package extdata:", source_path))
  }
}