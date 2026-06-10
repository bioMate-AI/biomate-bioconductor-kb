# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ramwas", "filematrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ramwas)
library(filematrix)

nsamples <- 20
ncpgs <- 1000
nsnps <- 500

# 1. covariates
covariates <- data.frame(
    sample = paste0("Sample_", 1:nsamples),
    age = runif(nsamples, 20, 80),
    sex = sample(c("M", "F"), nsamples, replace = TRUE)
)
write.table(covariates, "covariates.rds", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(covariates, "covariates.rds", sep = "\t", row.names = FALSE, quote = FALSE)

# 2. CpG_chromosome_names.txt
chr_names <- c("chr1", "chr2")
writeLines(chr_names, "CpG_chromosome_names.txt")

# 3. CpG_locations (filematrix)
cpg_locs <- matrix(0L, nrow = ncpgs, ncol = 2)
cpg_locs[,1] <- sample(1:2, ncpgs, replace = TRUE)
cpg_locs[,2] <- sort(sample(1:100000, ncpgs))

unlink(c("CpG_locations.bmat", "CpG_locations.desc.txt"))
fm_cpg <- fm.create("CpG_locations", nrow = ncpgs, ncol = 2, type = "integer")
fm_cpg[,] <- cpg_locs
close(fm_cpg)

# 4. Coverage (filematrix)
cov_mat <- matrix(runif(nsamples * ncpgs, 0, 100), nrow = nsamples, ncol = ncpgs)
unlink(c("Coverage.bmat", "Coverage.desc.txt", "Coverage.rownames.txt"))
fm_cov <- fm.create("Coverage", nrow = nsamples, ncol = ncpgs, type = "double")
fm_cov[,] <- cov_mat
rownames(fm_cov) <- covariates$sample
close(fm_cov)

# 5. SNPs (filematrix)
snp_mat <- matrix(sample(0:2, nsamples * nsnps, replace = TRUE), nrow = nsamples, ncol = nsnps)
unlink(c("SNPs.bmat", "SNPs.desc.txt", "SNPs.rownames.txt"))
fm_snp <- fm.create("SNPs", nrow = nsamples, ncol = nsnps, type = "integer")
fm_snp[,] <- snp_mat
rownames(fm_snp) <- covariates$sample
close(fm_snp)