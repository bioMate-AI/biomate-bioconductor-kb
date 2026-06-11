library(VegaMC)

# Find and copy breast_Affy500K.txt
breast_file <- list.files(system.file(package="VegaMC"), pattern="breast_Affy500K.txt", recursive=TRUE, full.names=TRUE)
if (length(breast_file) > 0 && file.exists(breast_file[1])) {
    file.copy(breast_file[1], "breast_Affy500K.txt", overwrite=TRUE)
} else {
    # Synthetic fallback
    breast_df <- data.frame(
        Name = paste0("probe", 1:10),
        Chr = rep(1, 10),
        Position = seq(1000, 10000, by=1000),
        Sample1_LRR = rnorm(10, 0, 0.1),
        Sample1_BAF = runif(10, 0, 1)
    )
    write.table(breast_df, "breast_Affy500K.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# Find and copy gist.txt
gist_file <- list.files(system.file(package="VegaMC"), pattern="gist.txt", recursive=TRUE, full.names=TRUE)
if (length(gist_file) > 0 && file.exists(gist_file[1])) {
    file.copy(gist_file[1], "gist.txt", overwrite=TRUE)
} else {
    # Synthetic fallback (unsorted)
    gist_df <- data.frame(
        Name = paste0("probe", 10:1),
        Chr = rep(1, 10),
        Position = seq(10000, 1000, by=-1000),
        Sample1_LRR = rnorm(10, 0, 0.1),
        Sample1_BAF = runif(10, 0, 1)
    )
    write.table(gist_df, "gist.txt", sep="\t", row.names=FALSE, quote=FALSE)
}