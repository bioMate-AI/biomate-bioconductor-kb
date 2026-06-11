# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("flowCore", "flowStats", "flowWorkspace", "ggcyto", "scales")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(flowCore)
library(flowStats)
library(flowWorkspace)
library(ggcyto)
data(ITN)

library(scales)
gs <- GatingSet(ITN)
trans.func <- asinh
inv.func <- sinh
trans.obj <- trans_new("myAsinh", trans.func, inv.func)
transList <- transformerList(colnames(ITN)[3:7], trans.obj)
gs <- transform(gs, transList)

lg <- lymphGate(gs_cyto_data(gs), channels=c("CD3", "SSC"),
                preselection="CD4", filterId="TCells",
                scale=2.5)
gs_pop_add(gs, lg)
recompute(gs)

qgate <- quadrantGate(gs_pop_get_data(gs, "TCells"), stains=c("CD4", "CD8"),
                      filterId="CD4CD8", sd=3)
gs_pop_add(gs, qgate, parent = "TCells")
recompute(gs)

gs <- normalize(gs, populations=c("CD4+CD8+", "CD4+CD8-", "CD4-CD8+", "CD4-CD8-"), 
                     dims=c("CD4", "CD8"), minCountThreshold = 50)

CD69rg <- rangeGate(gs_cyto_data(gs), stain="CD69",
                    alpha=0.75, filterId="CD4+CD8-CD69", sd=2.5)
gs_pop_add(gs, CD69rg, parent="CD4+CD8-")
recompute(gs)

gs <- normalize(gs, populations=c("CD4+CD8-CD69"), 
                     dims=c("CD69"), minCountThreshold = 50)

saveRDS(gs, "gs")