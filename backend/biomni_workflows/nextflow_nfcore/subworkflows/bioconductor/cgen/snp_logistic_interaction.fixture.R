# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CGEN", "cluster")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CGEN)
library(cluster)

# Reproduce the VIGNETTE'S OWN data-preparation code for Xdata

# code chunk number 2: load data
data(Xdata, package="CGEN")

# code chunk number 3: dummy vars
for (a in unique(Xdata[, "age.group"])) {
  dummyVar <- paste("age.group_", a, sep="")
  Xdata[, dummyVar] <- 0
  temp <- Xdata[, "age.group"] == a
  if (any(temp)) Xdata[temp, dummyVar] <- 1
}

# code chunk number 9: getMatchedSets
size <- ifelse(Xdata$ethnic.group == 3, 3, 4)
d <- daisy(Xdata[,c("age.group_1","gynSurgery.history","BRCA.history")])
mx <- getMatchedSets(d, CC=TRUE, NN=TRUE, ccs.var = Xdata$case.control,
	  strata.var = Xdata$ethnic.group, size = size, fixed = TRUE)
Xdata <- cbind(Xdata, CCStrat = mx$CC, NNStrat = mx$NN)

# Serialize the final Xdata object to Xdata.csv
write.csv(Xdata, "Xdata.csv", row.names = FALSE)