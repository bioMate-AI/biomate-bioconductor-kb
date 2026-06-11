# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tidysbml", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(tidysbml)
library(dplyr)

bed_data <- data.frame(
  chrom = c("chr1", "chr2"),
  chromStart = c(1000, 2000),
  chromEnd = c(1500, 2500)
)
write.table(bed_data, "regions.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

coldata <- data.frame(
  sample = c("sample1", "sample2"),
  condition = c("control", "treated")
)
write.csv(coldata, "coldata.csv", row.names = FALSE)

filepath <- system.file("extdata", "R-HSA-8937144.sbml", package = "tidysbml")
if (file.exists(filepath)) {
  sbml_list <- sbml_as_list(filepath)
  list_of_dfs <- as_dfs(sbml_list, type = "list")
  
  list_species <- sbml_as_list(filepath, component = "species")
  df_species <- as_df(list_species)
  
  list_react <- sbml_as_list(filepath, component = "reactions")
  dfs_about_reactions <- as_df(list_react)
  
  df_species_in_reactions <- dfs_about_reactions[[2]]
  
  edgelist <- df_species_in_reactions %>%
    select("reaction_id", "species") %>%
    `colnames<-`(c("source", "target"))
}