library(methimpute)

# ===== Step 1: Importing the data ===== #
file <- system.file("extdata", "arabidopsis_bsseeker.txt.gz", package="methimpute")
bsseeker.data <- importBSSeeker(file)

fasta.file <- system.file("extdata", "arabidopsis_sequence.fa.gz", package="methimpute")
cytosine.positions <- extractCytosinesFromFASTA(fasta.file, contexts = c('CG','CHG','CHH'))
methylome <- inflateMethylome(bsseeker.data, cytosine.positions)

# ===== Step 2: Obtain correlation parameters ===== #
distcor <- distanceCorrelation(methylome, separate.contexts = TRUE)
fit <- estimateTransDist(distcor)

# ===== Step 3: Methylation status calling (and imputation) ===== #
model <- callMethylationSeparate(data = methylome, transDist = fit$transDist, verbosity = 0)

# Save the model object
saveRDS(model, "model")

# ===== Step 4: Annotations ===== #
data("arabidopsis_genes", package = "methimpute")
data("arabidopsis_TEs", package = "methimpute")

# Save the annotations
save(arabidopsis_genes, arabidopsis_TEs, file = "annotations.RData")

# [biomate-fx-dual] emit each declared input under BOTH bare-token and .rds names
# so any input-staging harness collects the real serialized object under the
# exact name the workflow reads (bare token or <token>.rds).
.bm_dual <- function(b) {
  rds <- paste0(b, '.rds')
  if (file.exists(rds) && !file.exists(b)) file.copy(rds, b, overwrite=TRUE)
  if (file.exists(b) && !file.exists(rds)) file.copy(b, rds, overwrite=TRUE)
}
.bm_dual('model')
