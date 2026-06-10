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