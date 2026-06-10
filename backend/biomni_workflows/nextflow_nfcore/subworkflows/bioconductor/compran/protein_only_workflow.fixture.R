# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ComPrAn", "data.table")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ComPrAn)
library(data.table)

# Reproduce the VIGNETTE'S OWN data-preparation code to materialize the example object
# and serialize it to normalized_proteins.txt

# The vignette describes "dataNormProts.txt" from the package's extData as the
# "Normalised proteins input file". This file serves as the content for
# "normalized_proteins.txt" required by the workflow.
dataNormProts_path <- system.file("extData", "dataNormProts.txt", package = "ComPrAn")
normalized_proteins_data <- data.table::fread(dataNormProts_path)

# Serialize the data to "normalized_proteins.txt" in the working directory.
# The vignette describes the input as "text file with tab deliminated values".
data.table::fwrite(normalized_proteins_data, "normalized_proteins.txt", sep = "\t")

# Reproduce the VIGNETTE'S OWN data-preparation code to materialize the example object
# and serialize it to exampleGroup.txt

# The vignette explicitly uses "exampleGroup.txt" from the package's extData
# and reads it using data.table::fread, matching the workflow's requirement.
groupDataFileName_path <- system.file("extData", "exampleGroup.txt", package = "ComPrAn")
exampleGroup_data <- data.table::fread(groupDataFileName_path)

# Serialize the data to "exampleGroup.txt" in the working directory.
# The workflow excerpt shows data.table::fread, implying a text file format.
data.table::fwrite(exampleGroup_data, "exampleGroup.txt", sep = "\t")