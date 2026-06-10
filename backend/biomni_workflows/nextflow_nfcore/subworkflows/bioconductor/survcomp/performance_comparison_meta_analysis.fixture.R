# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("survcomp", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(survcomp)
library(Biobase)

# Load the breast cancer datasets provided by the package
data(breastCancerData)

# Extract gene symbols for reference
gsList <- tolower(fData(mainz7g)[,"Gene.symbol"])

# Compute concordance index for mainz7g
cindexall.mainz.small <- t(apply(X=exprs(mainz7g), MARGIN=1, function(x, y, z) { 
    tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE)
    return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper))
}, y=pData(mainz7g)[ ,"t.dmfs"], z=pData(mainz7g)[ ,"e.dmfs"]))

# Compute concordance index for transbig7g
cindexall.transbig.small <- t(apply(X=exprs(transbig7g), MARGIN=1, function(x, y, z) {
    tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE)
    return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper))
}, y=pData(transbig7g)[ ,"t.dmfs"], z=pData(transbig7g)[ ,"e.dmfs"]))

# Compute concordance index for vdx7g
cindexall.vdx.small <- t(apply(X=exprs(vdx7g), MARGIN=1, function(x, y, z) {
    tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE)
    return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper))
}, y=pData(vdx7g)[ ,"t.dmfs"], z=pData(vdx7g)[ ,"e.dmfs"]))

# Compute concordance index for upp7g
cindexall.upp.small <- t(apply(X=exprs(upp7g), MARGIN=1, function(x, y, z) {
    tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE)
    return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper))
}, y=pData(upp7g)[ ,"t.rfs"], z=pData(upp7g)[ ,"e.rfs"]))

# Compute concordance index for unt7g
cindexall.unt.small <- t(apply(X=exprs(unt7g), MARGIN=1, function(x, y, z) {
    tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE)
    return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper))
}, y=pData(unt7g)[ ,"t.dmfs"], z=pData(unt7g)[ ,"e.dmfs"]))

# Compute concordance index for nki7g
cindexall.nki.small <- t(apply(X=exprs(nki7g), MARGIN=1, function(x, y, z) {
    tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE)
    return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper))
}, y=pData(nki7g)[ ,"t.dmfs"], z=pData(nki7g)[ ,"e.dmfs"]))

# Save the computed concordance index objects to an RData file
save(cindexall.mainz.small, 
     cindexall.transbig.small, 
     cindexall.vdx.small, 
     cindexall.upp.small, 
     cindexall.unt.small, 
     cindexall.nki.small, 
     gsList,
     file="cindex_objects.RData")