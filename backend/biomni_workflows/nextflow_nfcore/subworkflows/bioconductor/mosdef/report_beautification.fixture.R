# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("mosdef", "macrophage", "DESeq2", "org.Hs.eg.db", "AnnotationDbi", "topGO")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library("mosdef")
  library("macrophage")
  library("DESeq2")
  library("org.Hs.eg.db")
  library("AnnotationDbi")
  library("topGO")
})

# Load the data
data(gse, package = "macrophage")
dds_macrophage <- DESeqDataSet(gse, design = ~ line + condition)
rownames(dds_macrophage) <- substr(rownames(dds_macrophage), 1, 15)

# Filter and subset to speed up the test fixture generation
keep <- rowSums(counts(dds_macrophage) >= 10) >= 6
dds_macrophage <- dds_macrophage[keep, ]
dds_macrophage <- dds_macrophage[1:min(1000, nrow(dds_macrophage)), ]

# Run DESeq2
dds_macrophage <- DESeq(dds_macrophage)

# Get results
res_macrophage_IFNg_vs_naive <- results(dds_macrophage, contrast = c("condition", "IFNg", "naive"), lfcThreshold = 1, alpha = 0.05)

# Add gene symbols
res_macrophage_IFNg_vs_naive$symbol <- AnnotationDbi::mapIds(
  org.Hs.eg.db, 
  keys = row.names(res_macrophage_IFNg_vs_naive), 
  column = "SYMBOL", 
  keytype = "ENSEMBL", 
  multiVals = "first" 
)

# Run topGO enrichment
res_enrich_macrophage_topGO <- run_topGO(
  de_container = dds_macrophage,
  res_de = res_macrophage_IFNg_vs_naive,
  ontology = "BP",
  mapping = "org.Hs.eg.db",
  FDR_threshold = 0.05,
  gene_id = "symbol",
  de_type = "up_and_down",
  add_gene_to_terms = TRUE,
  topGO_method2 = "elim",
  min_counts = 20,
  top_de = 700,
  verbose = TRUE
)

# Serialize the objects to the expected input files
saveRDS(res_macrophage_IFNg_vs_naive, "res_macrophage_IFNg_vs_naive.rds")
saveRDS(res_enrich_macrophage_topGO, "res_enrich_macrophage_topGO.rds")