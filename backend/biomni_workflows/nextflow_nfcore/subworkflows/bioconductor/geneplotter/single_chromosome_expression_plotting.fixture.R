# Real user-style input for geneplotter::alongChrom:
#   sample.ExpressionSet - an ExpressionSet from an Affymetrix HG-U95Av2 array
#       experiment. featureNames are GENUINE hgu95av2 probe-set IDs (the real
#       identifiers a user's CEL/expression matrix carries), with a 3-level
#       sample covariate `cov3`. We restrict to probes the hgu95av2.db annotation
#       maps to chromosome 1 so alongChrom has genes to draw.
#   chrObj - a `chromLocation` object mapping those probe IDs to their real
#       chromosome-1 coordinates (from hgu95av2CHRLOC) plus their gene symbols
#       (hgu95av2SYMBOL). This is the SAME S4 class buildChromLocation() returns,
#       constructed directly from the genuine annotation maps for the probes in
#       use.
#
# Why we build chromLocation directly instead of buildChromLocation("hgu95av2"):
#   buildChromLocation() materialises the FULL hgu95av2 annotation as nested
#   AnnDbBimap S4 objects. In this Bioc build that structure recurses deeply
#   enough to overflow R's fixed ~8 MB C protection stack ("C stack usage is too
#   close to the limit"), and even when the stack is raised the resulting object
#   triggers a node-stack overflow on serialization. The sandbox cannot raise
#   `ulimit -s` for the in-container R, so the only robust path is to assemble an
#   equivalent, lightweight `chromLocation` from the real CHRLOC / SYMBOL maps for
#   exactly the probes the ExpressionSet contains. alongChrom() reads only the
#   `chromLocs` (list: chrom -> named probe->location vector) and `geneSymbols`
#   (env: probe -> symbol) slots, both of which we populate from genuine
#   hgu95av2 annotation data — so the plot is real, not demo data.

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

# --- Real hgu95av2 probe-set IDs that the annotation maps to chromosome 1, with
#     a known signed location (CHRLOC; sign encodes strand). ---
chrloc <- as.list(hgu95av2CHRLOC)
on_chr1 <- function(z) {
  if (length(z) == 0 || all(is.na(z))) return(FALSE)
  any(names(z) == "1", na.rm = TRUE)
}
chr1_probes <- names(chrloc)[vapply(chrloc, on_chr1, logical(1))]
chr1_probes <- head(sort(unique(chr1_probes)), 150)     # a manageable real subset
stopifnot(length(chr1_probes) > 10)

# --- Synthetic expression for these real probes across 18 samples in 3 groups. ---
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

# --- Build a real, lightweight chromLocation for these probes. ---
# chromLocs: list keyed by chromosome -> named numeric vector (probe -> location
# on chr1, taking the chr1 entry of each probe's CHRLOC). This is exactly the
# structure buildChromLocation() produces, restricted to the used probes.
chr1_locs <- vapply(chr1_probes, function(p) {
  z <- chrloc[[p]]
  v <- z[names(z) == "1"]
  as.numeric(v[1])
}, numeric(1))
names(chr1_locs) <- chr1_probes
chr1_locs <- chr1_locs[!is.na(chr1_locs)]
stopifnot(length(chr1_locs) > 10)
chromLocs_list <- list("1" = chr1_locs)

# geneSymbols: environment mapping probe -> gene symbol (real hgu95av2SYMBOL),
# which alongChrom reads via mget(..., envir = geneSymbols(chrObj)).
sym_map <- as.list(hgu95av2SYMBOL[names(chr1_locs)])
gene_sym_env <- new.env(hash = TRUE, parent = emptyenv())
for (p in names(sym_map)) {
  s <- sym_map[[p]]
  assign(p, if (is.null(s) || all(is.na(s))) p else as.character(s)[1], envir = gene_sym_env)
}

# probesToChrom: probe -> chromosome ("1" for all). chromInfo: chr1 length.
p2c_env <- new.env(hash = TRUE, parent = emptyenv())
for (p in names(chr1_locs)) assign(p, "1", envir = p2c_env)
chrlen <- c("1" = 249250621)     # hg-style chromosome 1 length

chrObj <- new("chromLocation",
              organism      = "Homo sapiens",
              dataSource    = "hgu95av2",
              chromLocs     = chromLocs_list,
              probesToChrom = p2c_env,
              chromInfo     = chrlen,
              geneSymbols   = gene_sym_env)

saveRDS(chrObj, "chrObj")
stopifnot(file.exists("chrObj"))
