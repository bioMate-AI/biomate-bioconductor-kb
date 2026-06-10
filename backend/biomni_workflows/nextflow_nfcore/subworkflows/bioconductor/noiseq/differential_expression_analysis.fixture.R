# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("NOISeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(NOISeq)

# Reproduce data preparation from vignette
data(Marioni)

myfactors = data.frame(Tissue=c("Kidney","Liver","Kidney","Liver","Liver","Kidney","Liver",
                                "Kidney","Liver","Kidney"),
                       TissueRun = c("Kidney_1","Liver_1","Kidney_1","Liver_1","Liver_1",
                                     "Kidney_1","Liver_1","Kidney_2","Liver_2","Kidney_2"),
                       Run = c(rep("R1", 7), rep("R2", 3)))

mydata <- readData(data=mycounts,length=mylength, gc=mygc, biotype=mybiotypes,
                   chromosome=mychroms, factors=myfactors)

# Serialize the object to the expected input file
saveRDS(mydata, file="mydata.rds")