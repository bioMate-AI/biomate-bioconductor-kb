library(motifStack)
library(ade4)

# 1. Import PCM files shipped with the package
pcmFiles <- dir(system.file("extdata", package="motifStack"), pattern="\\.pcm$", full.names=TRUE)
motifs <- importMatrix(pcmFiles)

# 2. Convert PCM objects to PFM objects as required by the input spec
pfms <- lapply(motifs, function(m) {
    if (inherits(m, "pcm")) {
        mat <- pcm2pfm(m@mat)
        new("pfm", mat=mat, name=m@name)
    } else {
        m
    }
})
names(pfms) <- sapply(pfms, function(x) x@name)

# 3. Create a phylog object representing motif clustering
# We generate a synthetic distance matrix and hierarchical clustering for the motifs
set.seed(123)
dist_mat <- dist(matrix(runif(length(pfms) * 3), nrow = length(pfms)))
hc <- hclust(dist_mat)
hc$labels <- names(pfms)
phylog <- hclust2phylog(hc)

# 4. Serialize the objects to the expected input files
saveRDS(pfms, "pfms")
saveRDS(phylog, "phylog")