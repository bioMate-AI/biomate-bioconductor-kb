# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ddCt")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ddCt)

# --- Generate Experiment1.txt ---
# The vignette reads Experiment1.txt from the 'extdata' directory of the ddct package.
# We will copy this file to the current working directory to serve as the input fixture.
extdata_exp1_path <- system.file("extdata", "Experiment1.txt", package="ddCt")

# Read the original Experiment1.txt file.
# The ddCt package's SDMFrame function (used in the vignette) reads a tab-separated file
# with a header, containing at least "Sample", "Gene", and "Ct" columns.
exp1_data <- read.table(extdata_exp1_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)

# Write the data to Experiment1.txt in the current working directory.
# Ensure it's tab-separated, has a header, and no row names or quotes.
write.table(exp1_data, "Experiment1.txt", sep = "\t", row.names = FALSE, quote = FALSE)

# --- Generate SampleAnno.txt ---
# The vignette's default parameters set sampleAnnotationFile to NULL,
# meaning it doesn't explicitly use SampleAnno.txt from extdata.
# However, the prompt requires SampleAnno.txt as an input file.
# When sampleAnnotationFile is NULL, the workflow internally creates an
# AnnotatedDataFrame with a "Sample" column derived from the CtData.
# We will create a SampleAnno.txt file that matches this structure,
# and add a dummy "Group" column for potential future use with `columnForGrouping`.

# Extract unique sample names from Experiment1.txt
unique_samples <- unique(exp1_data$Sample)

# Create a data frame for SampleAnno.txt
sample_anno_data <- data.frame(Sample = unique_samples, stringsAsFactors = FALSE)

# Add a dummy 'Group' column. This is a common use case for sample annotation files.
# The vignette's `read.AnnotatedDataFrame` expects a tab-separated file with a header.
num_samples <- length(unique_samples)
if (num_samples > 1) {
  sample_anno_data$Group <- rep(c("Control", "Treatment"), length.out = num_samples)
} else {
  sample_anno_data$Group <- "Control" # Handle case with single sample
}

# Write the data to SampleAnno.txt in the current working directory.
# Ensure it's tab-separated, has a header, and no row names or quotes.
write.table(sample_anno_data, "SampleAnno.txt", sep = "\t", row.names = FALSE, quote = FALSE)