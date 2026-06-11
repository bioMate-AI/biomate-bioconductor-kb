# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Doscheda")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Doscheda)

# Extract the example dataset used in the vignette
data_df <- Doscheda::doschedaData

# Write the intensity data to intensity.csv
write.csv(data_df, "intensity.csv", row.names = FALSE)

# Reconstruct the channel names used in the vignette to build a coldata.csv
channelNames <- c(
  "Abundance..F1..126..Control..REP_1", 
  "Abundance..F1..127..Sample..REP_1", 
  "Abundance..F1..128..Sample..REP_1", 
  "Abundance..F1..129..Sample..REP_1", 
  "Abundance..F1..130..Sample..REP_1", 
  "Abundance..F1..131..Sample..REP_1", 
  "Abundance..F2..126..Control..REP_2", 
  "Abundance..F2..127..Sample..REP_2", 
  "Abundance..F2..128..Sample..REP_2", 
  "Abundance..F2..129..Sample..REP_2", 
  "Abundance..F2..130..Sample..REP_2", 
  "Abundance..F2..131..Sample..REP_2"
)

# Create a corresponding coldata data.frame
coldata <- data.frame(
  Sample = channelNames,
  Condition = rep(c("Control", rep("Sample", 5)), 2),
  Replicate = rep(c("REP_1", "REP_2"), each = 6)
)

# Write the coldata to coldata.csv
write.csv(coldata, "coldata.csv", row.names = FALSE)