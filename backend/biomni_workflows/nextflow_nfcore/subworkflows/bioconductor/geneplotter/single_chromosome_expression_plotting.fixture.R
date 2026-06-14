# Real user-style input for geneplotter::alongChrom:
#   sample.ExpressionSet - an ExpressionSet from an Affymetrix HG-U95Av2 array
#       experiment. featureNames are GENUINE hgu95av2 probe-set IDs (the real
#       identifiers a user's CEL/expression matrix carries), with a 3-level
#       sample covariate `cov3`. We restrict to probes that the hgu95av2.db
#       annotation maps to chromosome 1 so alongChrom has genes to draw.
#   chrObj - a chromLocation object built from the hgu95av2 annotation, mapping
#       those probe IDs to their chromosomal coordinates.
# The expression values are simulated (a user's own measurements), but the probe
# identifiers and chromosome mapping are real array/annotation data, not a
# packaged demo ExpressionSet.

.fx_deps <- c("geneplotter", "Biobase", "annotate", "hgu95av2.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin),
                            error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library(Biobase)
  library(geneplotter)
  library(annotate)
  library(hgu95av2.db)
})

set.seed(123)

# Real hgu95av2 probe-set IDs mapped to chromosome 1 by the annotation package.
chr_map <- as.list(hgu95av2CHR)
chr1_probes <- names(chr_map)[vapply(chr_map, function(x) any(x == "1") & !any(is.na(x)), logical(1))]
chr1_probes <- head(sort(unique(chr1_probes)), 150)        # a manageable real subset
stopifnot(length(chr1_probes) > 10)

# Synthetic expression for these real probes across 18 samples in 3 groups (cov3).
n_samp <- 18
mat <- matrix(rnorm(length(chr1_probes) * n_samp, mean = 7, sd = 2),
              nrow = length(chr1_probes), ncol = n_samp)
rownames(mat) <- chr1_probes
colnames(mat) <- sprintf("S%02d", seq_len(n_samp))

pheno <- data.frame(cov3 = factor(rep(c("A", "B", "C"), length.out = n_samp)),
                    row.names = colnames(mat))
eset <- ExpressionSet(assayData = mat,
                      phenoData = AnnotatedDataFrame(pheno),
                      annotation = "hgu95av2")
saveRDS(eset, "sample.ExpressionSet")

chrObj <- buildChromLocation("hgu95av2")
saveRDS(chrObj, "chrObj")
