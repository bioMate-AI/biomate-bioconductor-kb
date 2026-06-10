# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cydar", "ncdfFlow", "flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cydar)
library(ncdfFlow)
library(flowCore)

# 1. Reproduce the vignette's data-preparation code
set.seed(42)
ncells <- 2000 # Scaled down for faster fixture generation
nda <- 200
nmarkers <- 31
down.pos <- 1.8
up.pos <- 1.2
conditions <- rep(c("A", "B"), each=3)

combined <- rbind(matrix(rnorm(ncells*nmarkers, 1.5, 0.6), ncol=nmarkers),
                  matrix(rnorm(nda*nmarkers, down.pos, 0.3), ncol=nmarkers),
                  matrix(rnorm(nda*nmarkers, up.pos, 0.3), ncol=nmarkers))
combined[,31] <- rnorm(nrow(combined), 1, 0.5) # last marker is a QC marker.
combined <- 10^combined # raw intensity values

sample.id <- c(sample(length(conditions), ncells, replace=TRUE),
               sample(which(conditions=="A"), nda, replace=TRUE),
               sample(which(conditions=="B"), nda, replace=TRUE))
colnames(combined) <- paste0("Marker", seq_len(nmarkers))

collected.exprs <- list()
for (i in seq_along(conditions)) {
    mat <- combined[sample.id==i,,drop=FALSE]
    stuff <- list(mat)
    names(stuff) <- paste0("Sample", i)
    
    # Create flowFrame for cydar pooling
    collected.exprs[[i]] <- poolCells(stuff)
    
    # 2. Serialize to FCS files
    ff <- flowFrame(mat)
    write.FCS(ff, paste0("Sample", i, ".fcs"))
}

names(collected.exprs) <- paste0("Sample", seq_along(conditions))
collected.exprs <- ncdfFlowSet(as(collected.exprs, "flowSet"))

# 3. Serialize the ncdfFlowSet object
saveRDS(collected.exprs, "ncdfFlowSet.rds")

# Ensure ncdfFlowSet is also saved in its native directory format if needed by the workflow
if (exists("save_ncfs")) {
    save_ncfs(collected.exprs, path="ncdfFlowSet_data")
}