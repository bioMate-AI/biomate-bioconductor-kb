# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bacon", "BiocParallel")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bacon)
library(BiocParallel) # Although not strictly needed for data generation, it's in the vignette.

# Data preparation code from the vignette (Section 3: Multiple sets of test-statistics)
set.seed(12345)
biases <- runif(6, -0.2, 0.2)
inflations <- runif(6, 1, 1.3)
es <- matrix(nrow=5000, ncol=6)
for(i in 1:6) es[,i] <- rnormmix(5000, c(0.9, biases[i], inflations[i], 0, 4, 1), shuffle=FALSE)
se <- replicate(6, 0.8*sqrt(4/rchisq(5000,df=4)))
colnames(es) <- colnames(se) <- LETTERS[1:ncol(se)]
rownames(es) <- rownames(se) <- 1:5000

# Serialize 'es' object
saveRDS(es, "es.rds")
write.csv(es, "es.rds", row.names = TRUE, quote = FALSE)
write.table(es, "es.rds", sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)

# Serialize 'se' object
saveRDS(se, "se.rds")
write.csv(se, "se.rds", row.names = TRUE, quote = FALSE)
write.table(se, "se.rds", sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)