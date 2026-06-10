# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RankProd")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RankProd)

# Reproduce the VIGNETTE'S OWN data-preparation code
# Load the 'arab' dataset
data(arab)

# Subset the data as shown in vignette chunk 9
# arab.sub will be the expression matrix
arab.sub <- arab[,which(arab.origin==1)]
# arab.cl.sub will be the class labels vector
arab.cl.sub <- arab.cl[which(arab.origin==1)]

# Serialize the objects to the declared input files

# Write expression_data to normalized_expression_matrix.tsv
# The workflow reads this with:
# expression_data <- read.delim("normalized_expression_matrix.tsv", row.names = 1, header = TRUE, check.names = FALSE)
write.table(arab.sub,
            "normalized_expression_matrix.tsv",
            sep = "\t",
            row.names = TRUE,   # Matches row.names = 1
            col.names = TRUE,   # Matches header = TRUE
            quote = FALSE)      # Prevents quoting of cell values

# Write class_labels to class_labels.txt
# The workflow reads this with:
# arab.cl.sub <- scan("class_labels.txt", quiet = TRUE)
write(arab.cl.sub,
      "class_labels.txt",
      sep = "\n") # Each label on a new line, scan can handle this.