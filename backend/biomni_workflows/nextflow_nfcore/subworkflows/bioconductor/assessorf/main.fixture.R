# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DECIPHER", "AssessORF")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DECIPHER)
library(AssessORF)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Define the database file name for the fixture
databaseFile <- "databaseFile.sqlite"

# Copy the pre-saved database file from the package's extdata
# This bypasses the need for internet connection and the Seqs2DB loop,
# as done in the vignette's 'echo = FALSE' block for robustness.
file.copy(system.file("extdata", "Adenoviridae.sqlite", package = "AssessORF"),
          databaseFile,
          overwrite = TRUE)

# Determine the identifiers for the genomes in the database.
# This logic follows the vignette's 'echo = FALSE' block where
# identifiers are set based on the length of 'pass' if the database
# was copied. 'pass' would have been initialized based on 'ftps'.
relGenomesFile <- system.file("extdata",
                           "AdenoviridaeGenomes.csv",
                           package = "AssessORF")
genomesTable <- read.csv(relGenomesFile, stringsAsFactors = FALSE)[1:13, ]
ftps <- genomesTable$GenBank.FTP
pass <- logical(length(ftps)) # length(ftps) is 13
identifiers <- as.character(seq_along(pass)) # This results in c("1", "2", ..., "13")

# Load and parse the Prodigal output file to get gene positions and strand
currProdigal <- readLines(system.file("extdata",
                                      "MGAS5005_Prodigal.sco",
                                      package = "AssessORF"))[-1:-2]

prodigalLeft <- as.numeric(sapply(strsplit(currProdigal, "_", fixed=TRUE), `[`, 2L))
prodigalRight <- as.numeric(sapply(strsplit(currProdigal, "_", fixed=TRUE), `[`, 3L))
prodigalStrand <- sapply(strsplit(currProdigal, "_", fixed=TRUE), `[`, 4L)

# 2. Serialize the data to EACH declared input file in the EXACT format the workflow reads

# Save geneLeftPos
writeLines(as.character(prodigalLeft), "geneLeftPos")

# Save geneRightPos
writeLines(as.character(prodigalRight), "geneRightPos")

# Save geneStrand
writeLines(prodigalStrand, "geneStrand")

# The 'databaseFile' itself ("databaseFile.sqlite") has already been created
# and populated by the file.copy command above.