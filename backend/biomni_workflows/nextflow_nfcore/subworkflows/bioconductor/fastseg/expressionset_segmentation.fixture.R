# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("fastseg", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(fastseg)
library(Biobase)

# Reproduce data preparation from the vignette
data(coriell)

samplenames <- colnames(coriell)[4:5]
data <- as.matrix(coriell[4:5])
#data[is.na(data)] <- median(data, na.rm=TRUE) # This line is commented out in the vignette
chrom <- coriell$Chromosome
maploc <- coriell$Position

# Create the ExpressionSet object as shown in the vignette (Section 2.2.2)
eSet <- Biobase::ExpressionSet()
assayData(eSet) <- list(intensity=data)

featureData(eSet) <- AnnotatedDataFrame(
        data=data.frame(
                chrom = paste("chr",chrom,sep=""),
                start = maploc,
                end = maploc,stringsAsFactors=FALSE))
phenoData(eSet) <- AnnotatedDataFrame(
        data=data.frame(samples=samplenames))
sampleNames(eSet) <- samplenames

# Serialize the eSet object to eSet.rds
saveRDS(eSet, "eSet.rds")