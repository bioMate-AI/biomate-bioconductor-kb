# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("rsbml")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(rsbml)

# Read the SBML document as demonstrated in the vignette
sbml_file <- system.file("sbml", "GlycolysisLayout.xml", package = "rsbml")
doc <- rsbml_read(sbml_file, dom = FALSE)

# Convert to S4 Document Object Model (DOM)
dom <- rsbml_dom(doc)

# Extract species IDs from the model
species_ids <- sapply(species(model(dom)), id)

# Write the extracted data to the required input.csv file
write.csv(data.frame(SpeciesID = species_ids), "input.csv", row.names = FALSE)