# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(flowCore))

# Load example data shipped with flowCore
data(GvHD)

# 1. Create the raw flow cytometry data file
write.FCS(GvHD[[1]], "file.name.FCS")

# 2. Create the directory and single-stained compensation control FCS files
dir.create("fcs.dir", showWarnings = FALSE)
write.FCS(GvHD[[2]], file.path("fcs.dir", "control_FL1.fcs"))
write.FCS(GvHD[[3]], file.path("fcs.dir", "control_FL2.fcs"))
write.FCS(GvHD[[4]], file.path("fcs.dir", "control_FL3.fcs"))

# 3. Create the CSV file matching control filenames to channels
comp_match <- data.frame(
    filename = c("control_FL1.fcs", "control_FL2.fcs", "control_FL3.fcs"),
    channel = c("FL1-H", "FL2-H", "FL3-H"),
    stringsAsFactors = FALSE
)
write.csv(comp_match, "comp_match.csv", row.names = FALSE)