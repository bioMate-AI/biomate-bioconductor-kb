# [biomate] structured fixture (rule: package_example_data) — deterministic, no LLM
# fgga ships the vignette example data set `CfData`, a list whose elements provide the three
# workflow inputs:
#   dxCf       (proteins x features expression/feature matrix)
#   tableCfGO  (proteins x GO-term binary annotation matrix)
#   nodesGO    (character vector of GO-term node ids)
# load_input() accepts <name>.rds / <name>.csv / <name>.txt; emit .rds (real objects) AND the
# bare-token name so any input-staging harness collects the real serialized object.
.fx_deps <- c("fgga")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(fgga)

data(CfData)

# CfData is a named list in the fgga vignette; pull the three inputs robustly.
.get <- function(nm) {
  if (exists("CfData") && !is.null(CfData[[nm]])) return(CfData[[nm]])
  if (exists(nm)) return(get(nm))
  stop(paste0("fgga example component not found: ", nm))
}

dxCf      <- .get("dxCf")
tableCfGO <- .get("tableCfGO")
nodesGO   <- .get("nodesGO")

.emit <- function(obj, base) {
  rds <- paste0(base, ".rds")
  saveRDS(obj, rds)
  file.copy(rds, base, overwrite = TRUE)   # bare-token alias for staging harnesses
}

.emit(dxCf, "dxCf")
.emit(tableCfGO, "tableCfGO")
.emit(nodesGO, "nodesGO")
