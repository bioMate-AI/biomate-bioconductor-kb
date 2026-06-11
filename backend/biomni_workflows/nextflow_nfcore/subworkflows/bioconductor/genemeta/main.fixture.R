# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GeneMeta", "RColorBrewer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GeneMeta)
library(RColorBrewer)

# Load the Nevins dataset
data(Nevins)

# Set seed for reproducibility as in the vignette
set.seed(1609)

# Split the Nevins dataset into Split1 and Split2
thestatus  <- pData(Nevins)[,"ER.status"]
group1     <- which(thestatus=="pos")
group2     <- which(thestatus=="neg")
rrr        <- c(sample(group1, floor(length(group1)/2)),
		sample(group2,ceiling(length(group2)/2)))
Split1     <- Nevins[,rrr]
Split2     <- Nevins[,-rrr]

# Extract and process ER status for Split1 and Split2
Split1.ER<-pData(Split1)[,"ER.status"]
levels(Split1.ER) <- c(0,1)
Split1.ER<- as.numeric(as.character(Split1.ER))

Split2.ER<-pData(Split2)[,"ER.status"]
levels(Split2.ER) <- c(0,1)
Split2.ER<- as.numeric(as.character(Split2.ER))

# Save the generated objects to .rds files
saveRDS(Split1, "Split1.rds")
saveRDS(Split2, "Split2.rds")
saveRDS(Split1.ER, "Split1.rds")
saveRDS(Split2.ER, "Split2.rds")