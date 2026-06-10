# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioCor", "org.Hs.eg.db", "reactome.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("BioCor")
library("org.Hs.eg.db")
library("reactome.db")

# Reproduce vignette's data preparation for 'sim'
# This section is copied verbatim from the "4.1 Preparation" and "4.2 Pathway similarities" sections of the vignette.
genesKegg <- as.list(org.Hs.egPATH)
genesReact <- as.list(reactomeEXTID2PATHID)
# Remove genes and pathways which are not from human pathways
genesReact <- lapply(genesReact, function(x){
  unique(grep("R-HSA-", x, value = TRUE))
})
genesReact <- genesReact[lengths(genesReact) >= 1]

# Create 'pathways' object as in the vignette to generate 'sim'
# The vignette uses sample() which can lead to different results.
# For reproducibility in a test fixture, a seed is set.
set.seed(123) # For reproducibility of the sample() call
pathways <- sample(unique(unlist(genesReact)), 10)

# Generate the 'sim' object as a matrix of pathway similarities
sim <- mpathSim(pathways, genesReact)

# Generate a plausible 'expr' object
# The BioCor vignette does not provide an 'expr' object.
# The workflow reads 'expr' as a matrix (from .rds or .csv).
# We create a small, generic numeric matrix with row and column names
# to satisfy the workflow's input requirement.
set.seed(456) # For reproducibility of random expression data
expr <- matrix(rnorm(5 * 3), nrow = 5, ncol = 3) # Example: 5 genes, 3 samples
rownames(expr) <- paste0("Gene", 1:5)
colnames(expr) <- paste0("Sample", 1:3)

# Serialize objects to the declared input files
# The workflow checks for .