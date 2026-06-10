library(tanggle)
library(phangorn)
library(ggtree)
library(ape)

# Locate the shipped woodmouse.nxs file from the phangorn package
source_file <- system.file("extdata/trees", "woodmouse.nxs", package = "phangorn")

# Copy the file to the working directory to serve as the input fixture
if (file.exists(source_file)) {
    file.copy(source_file, "woodmouse.nxs", overwrite = TRUE)
} else {
    # Fallback: generate the split network from the woodmouse dataset as described in the vignette
    data(woodmouse, package = "ape")
    dist_mat <- dist.dna(woodmouse)
    nnet <- neighborNet(dist_mat)
    write.nexus.networx(nnet, "woodmouse.nxs")
}