# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ANCOMBC", "tidyverse", "microbiome", "phyloseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ANCOMBC)
library(tidyverse)
library(microbiome)
library(phyloseq)

# Import example data from the microbiome package
data(atlas1006, package = "microbiome")

# Subset to baseline
pseq = phyloseq::subset_samples(atlas1006, time == 0)

# Re-code the bmi group
meta_data = microbiome::meta(pseq)
meta_data$bmi = recode(meta_data$bmi_group,
                       obese = "obese",
                       severeobese = "obese",
                       morbidobese = "obese")

# Manually change the reference level
meta_data$bmi = factor(meta_data$bmi, levels = c("obese", "overweight", "lean"))

# Create the region variable
meta_data$region = recode(as.character(meta_data$nationality),
                          Scandinavia = "NE",
                          UKIE = "NE",
                          SouthEurope = "SE",
                          CentralEurope = "CE",
                          EasternEurope = "EE",
                          .missing = "unknown")

phyloseq::sample_data(pseq) = meta_data

# Subset to lean, overweight, and obese subjects
pseq = phyloseq::subset_samples(pseq, bmi %in% c("lean", "overweight", "obese"))

# Discard "EE" as it contains only 1 subject
# Discard subjects with missing values of region
pseq = phyloseq::subset_samples(pseq, !region %in% c("EE", "unknown"))

# Extract abundance and metadata
abundance_data = microbiome::abundances(pseq)
meta_data = microbiome::meta(pseq)

# Write to the required input files
write.table(abundance_data, file = "microbiome_counts.tsv", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
write.table(meta_data, file = "sample_metadata.tsv", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)