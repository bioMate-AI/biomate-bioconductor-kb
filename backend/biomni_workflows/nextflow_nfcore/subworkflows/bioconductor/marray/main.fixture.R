library(marray)

datadir <- system.file("swirldata", package="marray")
if (nzchar(datadir)) {
    files_to_copy <- list.files(datadir, full.names = TRUE)
    invisible(file.copy(files_to_copy, ".", overwrite = TRUE))
} else {
    # Fallback synthetic data if directory is missing
    targets <- data.frame(
        slideNumber = 81,
        FileName = "swirl.1.spot",
        Cy3 = "swirl",
        Cy5 = "WT",
        date = "2001-09-20",
        comments = "synthetic"
    )
    write.table(targets, "SwirlSample.txt", sep="\t", row.names=FALSE, quote=FALSE)
    
    gal_content <- c(
        "ATF\t1.0",
        "5\t4",
        "Type=GenePix ArrayList V1.0",
        "BlockCount=1",
        "Block1= 15, 15, 100, 10, 20, 20, 100",
        "Block\tRow\tColumn\tID\tName",
        "1\t1\t1\tcontrol\tcontrol",
        "1\t1\t2\tgene1\tgene1"
    )
    writeLines(gal_content, "fish.gal")
    
    spot_data <- data.frame(
        Block = 1,
        Row = 1,
        Column = 1:2,
        ID = c("control", "gene1"),
        Name = c("control", "gene1"),
        Rmean = c(100, 500),
        Gmean = c(100, 400),
        Rbg = c(10, 15),
        Gbg = c(10, 12)
    )
    write.table(spot_data, "swirl.1.spot", sep="\t", row.names=FALSE, quote=FALSE)
}