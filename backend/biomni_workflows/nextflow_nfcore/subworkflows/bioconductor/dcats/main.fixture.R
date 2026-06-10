# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DCATS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DCATS)

# Set seed for reproducibility as in the vignette
set.seed(6171)

# 1. Prepare sim_count and sim_design
K <- 3
totals1 = c(100, 800, 1300, 600)
totals2 = c(250, 700, 1100)
diri_s1 = rep(1, K) * 20
diri_s2 = rep(1, K) * 20
simil_mat = create_simMat(K, confuse_rate=0.2)
sim_dat <- DCATS::simulator_base(totals1, totals2, diri_s1, diri_s2, simil_mat)

sim_count <- rbind(sim_dat$numb_cond1, sim_dat$numb_cond2)
sim_design <- data.frame(condition = c("g1", "g1", "g1", "g1", "g2", "g2", "g2"))

# 2. Prepare knnGraphs and labels
data(simulation)
knnGraphs <- simulation$knnGraphs
labels <- simulation$labels

# 3. Prepare svmDF
data(Kang2017)
svmDF <- Kang2017$svmDF

# Serialize objects to files using saveRDS as it's the most robust for R objects
saveRDS(sim_count, "sim_count")
saveRDS(sim_design, "sim_design")
saveRDS(knnGraphs, "knnGraphs")
saveRDS(labels, "labels")
saveRDS(svmDF, "svmDF")