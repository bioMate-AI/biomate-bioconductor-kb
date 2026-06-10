# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("glmSparseNet", "survival")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(glmSparseNet)
library(survival)

set.seed(123)

# The vignette uses curatedTCGAData which requires online access.
# We construct a synthetic dataset matching the vignette's structure and exact gene names.
smallSubset <- c(
    "AAK1", "ADRB1", "AK7", "ALK", "APOBEC3F", "ARID1B", "BAMBI", "BRAF", "BTG1",
    "CACNG8", "CASP12", "CD5", "CDA", "CEP72", "CPD", "CSF2RB", "CSN3", "DCT",
    "DLG3", "DLL3", "DPP4", "DSG1", "EDA2R", "ERP27", "EXD1", "GABBR2", "GADD45A",
    "GBP1", "HTR1F", "IFNK", "IRF2", "IYD", "KCNJ11", "KRTAP5-6", "MAFA", "MAGEB4",
    "MAP2K6", "MCTS1", "MMP15", "MMP9", "NFKBIA", "NLRC4", "NT5C1A", "OPN4",
    "OR13C5", "OR13C8", "OR2T6", "OR4K2", "OR52E6", "OR5D14", "OR5H1", "OR6C4",
    "OR7A17", "OR8J3", "OSBPL1A", "PAK6", "PDE11A", "PELO", "PGK1", "PIK3CB",
    "PMAIP1", "POLR2B", "POP1", "PPFIA3", "PSME1", "PSME2", "PTEN", "PTGES3",
    "QARS", "RABGAP1", "RBM3", "RFC3", "RGPD8", "RPGRIP1L", "SAV1", "SDC1",
    "SDC3", "SEC16B", "SFPQ", "SFRP5", "SIPA1L1", "SLC2A14", "SLC6A9", "SPATA5L1",
    "SPINT1", "STAR", "STXBP5", "SUN3", "TACC2", "TACR1", "TAGLN2", "THPO",
    "TNIP1", "TP53", "TRMT2B", "TUBB1", "VDAC1", "VSIG8", "WNT3A", "WWOX",
    "XRCC4", "YME1L1", "ZBTB11", "ZSCAN21"
)

n_samples <- 100
xdata <- matrix(rnorm(n_samples * length(smallSubset)), nrow = n_samples, ncol = length(smallSubset))
rownames(xdata) <- paste0("Patient_", 1:n_samples)
colnames(xdata) <- smallSubset

ydata <- data.frame(
    time = sample(10:1000, n_samples, replace = TRUE),
    status = sample(0:1, n_samples, replace = TRUE),
    row.names = rownames(xdata)
)

# Serialize objects to the declared input files
saveRDS(xdata, "xdata.rds")
saveRDS(ydata, "ydata.rds")