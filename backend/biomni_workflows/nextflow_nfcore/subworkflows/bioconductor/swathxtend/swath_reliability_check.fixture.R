library(SwathXtend)

# Copy required files from the package installation
files_to_copy <- c("Lib2.txt", "Swath_result_seed.xlsx", "Swath_result_ext.xlsx")

for (f in files_to_copy) {
    src <- system.file("files", f, package="SwathXtend")
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        src_alt <- list.files(system.file(package="SwathXtend"), pattern=paste0("^", f, "$"), recursive=TRUE, full.names=TRUE)
        if (length(src_alt) > 0) {
            file.copy(src_alt[1], f, overwrite = TRUE)
        }
    }
}

# Handle Lib2_3.txt which might be shipped or might need to be generated
lib2_3_src <- system.file("files", "Lib2_3.txt", package="SwathXtend")
if (file.exists(lib2_3_src)) {
    file.copy(lib2_3_src, "Lib2_3.txt", overwrite = TRUE)
} else {
    lib2_3_alt <- list.files(system.file(package="SwathXtend"), pattern="^Lib2_3\\.txt$", recursive=TRUE, full.names=TRUE)
    if (length(lib2_3_alt) > 0) {
        file.copy(lib2_3_alt[1], "Lib2_3.txt", overwrite = TRUE)
    } else {
        # Generate it as per vignette
        lib2_src <- system.file("files", "Lib2.txt", package="SwathXtend")
        lib3_src <- system.file("files", "Lib3.txt", package="SwathXtend")
        
        if (!file.exists(lib2_src)) {
            lib2_src <- list.files(system.file(package="SwathXtend"), pattern="^Lib2\\.txt$", recursive=TRUE, full.names=TRUE)[1]
        }
        if (!file.exists(lib3_src)) {
            lib3_src <- list.files(system.file(package="SwathXtend"), pattern="^Lib3\\.txt$", recursive=TRUE, full.names=TRUE)[1]
        }
        
        if (!is.na(lib2_src) && !is.na(lib3_src) && file.exists(lib2_src) && file.exists(lib3_src)) {
            Lib2_3 <- buildSpectraLibPair(lib2_src, lib3_src, clean=TRUE, 
                                          nomc=TRUE, nomod=TRUE, plot=FALSE, 
                                          outputFormat = "peakview",
                                          outputFile = "Lib2_3.txt")
        }
    }
}