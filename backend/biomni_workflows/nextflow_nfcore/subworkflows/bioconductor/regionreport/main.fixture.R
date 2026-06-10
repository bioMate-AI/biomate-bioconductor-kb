# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bumphunter", "GenomicRanges", "GenomeInfoDb")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("bumphunter")
library("GenomicRanges")
library("GenomeInfoDb")

# Create data from the vignette
pos <- list(
    pos1 = seq(1, 1000, 35),
    pos2 = seq(2001, 3000, 35),
    pos3 = seq(1, 1000, 50)
)
chr <- rep(paste0("chr", c(1, 1, 2)), times = sapply(pos, length))
pos <- unlist(pos, use.names = FALSE)

# Find clusters
cl <- clusterMaker(chr, pos, maxGap = 300)

# Build simulated bumps
Indexes <- split(seq_along(cl), cl)
beta1 <- rep(0, length(pos))
for (i in seq(along = Indexes)) {
    ind <- Indexes[[i]]
    x <- pos[ind]
    z <- scale(x, median(x), max(x) / 12)
    beta1[ind] <- i * (-1)^(i + 1) * pmax(1 - abs(z)^3, 0)^3
}

# Build data
beta0 <- 3 * sin(2 * pi * pos / 720)
X <- cbind(rep(1, 20), rep(c(0, 1), each = 10))
set.seed(23852577)
error <- matrix(rnorm(20 * length(beta1), 0, 1), ncol = 20)
y <- t(X[, 1]) %x% beta0 + t(X[, 2]) %x% beta1 + error

# Perform bumphunting
tab <- bumphunter(y, X, chr, pos, cl, cutoff = .5)

# Build GRanges
regions <- GRanges(
    seqnames = tab$table$chr,
    IRanges(start = tab$table$start, end = tab$table$end),
    strand = "*",
    value = tab$table$value,
    area = tab$table$area,
    cluster = tab$table$cluster,
    L = tab$table$L,
    clusterL = tab$table$clusterL
)

# Assign chr lengths (hardcoded to avoid offline failure with getChromInfoFromUCSC)
seqlengths(regions) <- c(chr1 = 249250621, chr2 = 243199373)[names(seqlengths(regions))]

# Serialize the object to the expected input file
saveRDS(regions, "regions")