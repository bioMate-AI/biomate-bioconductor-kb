# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ASGSCA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ASGSCA)

# Reproduce QCAHS1
data("QCAHS")
ObservedVar <- c("TaqIB","HindIII","G1302A","G1564A","G308A","G238A","HDL","LDL","APOB",
                 "TG","Glucose","Insulin")
QCAHS1 <- data.frame(QCAHS$TaqIB,QCAHS$HindIII,QCAHS$G1302A,QCAHS$G1564A,QCAHS$G308A,QCAHS$G238A,
                     QCAHS$HDL,QCAHS$LDL,QCAHS$APOB,QCAHS$TG,QCAHS$Glucose,QCAHS$Insulin)
colnames(QCAHS1) <- ObservedVar

# Reproduce W0 and B0
LatentVar <- c("CETP","LPL","PGC","TNFa","Lipid metabolism","Energy metabolism")
W0 <- matrix(rep(0,12*6),nrow=12,ncol=6, dimnames=list(ObservedVar,LatentVar))
W0[1,1]=W0[2,2]=W0[3:4,3]=W0[5:6,4]=W0[7:10,5]=W0[8:12,6]=1

B0 <- matrix(rep(0,6*6),nrow=6,ncol=6, dimnames=list(LatentVar,LatentVar))
B0[1:3,5]=B0[3:4,6]=1

# Serialize objects to files
# QCAHS1 is a data.frame, workflow reads it with read.csv
write.csv(QCAHS1, "QCAHS1", row.names = FALSE)

# W0 and B0 are matrices, workflow reads with readRDS (preferred for R objects)
saveRDS(W0, "W0")
saveRDS(B0, "B0")