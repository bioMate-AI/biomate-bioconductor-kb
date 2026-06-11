# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("gCrisprTools", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(gCrisprTools)
library(Biobase)

# Load the standard example datasets shipped with gCrisprTools
data("es", package = "gCrisprTools")
data("ann", package = "gCrisprTools")
data("sk", package = "gCrisprTools")
data("aln", package = "gCrisprTools")
data("essential.genes", package = "gCrisprTools")

# Construct a GeneSetDb object for pathway enrichment
if (requireNamespace("sparrow", quietly = TRUE)) {
    gs_df <- data.frame(
        collection = rep("c2", 10),
        name = rep("example_pathway", 10),
        feature_id = ann$geneID[1:10],
        stringsAsFactors = FALSE
    )
    genesetdb <- sparrow::GeneSetDb(gs_df)
} else {
    # Fallback if sparrow is not available in the environment
    genesetdb <- list(
        collection = "c2", 
        name = "example_pathway", 
        feature_id = ann$geneID[1:10]
    )
}

# Serialize all objects to the working directory as expected by the workflow
saveRDS(es, "es.rds")
saveRDS(ann, "ann.rds")
saveRDS(sk, "sk.rds")
saveRDS(aln, "aln.rds")
saveRDS(essential.genes, "essential.genes.rds")
saveRDS(genesetdb, "genesetdb.rds")