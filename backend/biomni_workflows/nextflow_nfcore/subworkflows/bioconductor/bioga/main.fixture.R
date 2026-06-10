# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioGA", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BioGA)
library(SummarizedExperiment)

# Define parameters
num_genes <- 1000
num_samples <- 10

# Define parameters for genetic algorithm (not directly used for data generation, but part of vignette context)
population_size <- 100
generations <- 20
mutation_rate <- 0.1

# Generate example genomic data using SummarizedExperiment
counts <- matrix(rpois(num_genes * num_samples, lambda = 10), nrow = num_genes )
rownames(counts) <- paste0("Gene", 1:num_genes)
colnames(counts) <- paste0("Sample", 1:num_samples)

# Create SummarizedExperiment object
se <- SummarizedExperiment::SummarizedExperiment(assays = list(counts = counts))

# Convert SummarizedExperiment to matrix for compatibility with BioGA package
genomic_data <- assay(se)

# Serialize the genomic_data matrix to the input file "genomic_data.matrix"
# The workflow reads this as a delimited text file with header and row names.
write.table(genomic_data, 
            file = "genomic_data.matrix", 
            sep = "\t", 
            quote = FALSE, 
            row.names = TRUE, 
            col.names = TRUE)