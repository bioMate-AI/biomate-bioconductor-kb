# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("compcodeR", "ape")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(compcodeR)
library(ape)

# Generate synthetic data using compcodeR's built-in simulator
B_625_625 <- generateSyntheticData(
    dataset = "B_625_625", 
    n.vars = 1250, 
    samples.per.cond = 5, 
    n.diffexp = 125, 
    repl.id = 1, 
    seqdepth = 1e7, 
    fraction.upregulated = 0.5, 
    between.group.diffdisp = FALSE, 
    filter.threshold.total = 1, 
    filter.threshold.mediancpm = 0, 
    fraction.non.overdispersed = 0, 
    output.file = "B_625_625_5spc_repl1.rds"
)

# Extract count matrix and sample annotations from the compData object
count_mat <- compcodeR::count.matrix(B_625_625)
samp_ann <- compcodeR::sample.annotations(B_625_625)

# Add species IDs to sample annotations to match the phylogenetic tree
samp_ann$species <- rep(c("Species1", "Species2"), length.out = nrow(samp_ann))

# Create a phylogenetic tree in ape phylo format
tree_obj <- rtree(2, tip.label = c("Species1", "Species2"))

# Create a matrix of orthologous gene lengths
len_mat <- matrix(1000, nrow = nrow(count_mat), ncol = ncol(count_mat))
rownames(len_mat) <- rownames(count_mat)
colnames(len_mat) <- colnames(count_mat)

# Serialize objects to the declared input files
saveRDS(count_mat, "count.matrix")
saveRDS(samp_ann, "sample.annotations")
saveRDS(tree_obj, "tree")
saveRDS(len_mat, "length.matrix")