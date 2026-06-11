# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("microbiomeDASim")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(microbiomeDASim)

# Generate simulated microbiome data as shown in the vignette
bug_gen <- gen_norm_microbiome(features=6, diff_abun_features=3, n_control=30,
                                n_treat=20, control_mean=2, sigma=2,
                                num_timepoints=4, t_interval=c(0, 3),
                                rho=0.9, corr_str="compound",
                                func_form="M", beta=c(4, 3), IP=c(2, 3.3, 6),
                                missing_pct=0.2, missing_per_subject=2,
                                miss_val=0)

# Extract the abundance matrix
abundance <- bug_gen$Y

# Ensure row and column names exist for the CSV outputs
if (is.null(colnames(abundance))) {
    colnames(abundance) <- paste0("Sample_", seq_len(ncol(abundance)))
}
if (is.null(rownames(abundance))) {
    rownames(abundance) <- paste0("Feature_", seq_len(nrow(abundance)))
}

# Write abundance data
write.csv(abundance, "abundance.csv", row.names=TRUE)

# Construct corresponding coldata based on the simulation parameters
# 30 control subjects and 20 treatment subjects, each with 4 timepoints
coldata <- data.frame(
    SampleID = colnames(abundance),
    Group = rep(c("Control", "Treatment"), c(30 * 4, 20 * 4)),
    Timepoint = rep(1:4, times = 50)
)
rownames(coldata) <- coldata$SampleID

# Write coldata
write.csv(coldata, "coldata.csv", row.names=TRUE)