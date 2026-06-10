library(Chicago)
library(PCHiCdata)

dataPath <- system.file("extdata", package="PCHiCdata")
testDesignDir <- file.path(dataPath, "hg19TestDesign")
testDataPath <- file.path(dataPath, "GMchinputFiles")

# Required design files
design_files <- c(
    "h19_chr20and21.rmap", 
    "h19_chr20and21.baitmap", 
    "h19_chr20and21.npb", 
    "h19_chr20and21.nbpb", 
    "h19_chr20and21.poe"
)

for (f in design_files) {
    src <- file.path(testDesignDir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback search
        src_alt <- list.files(dataPath, pattern = f, recursive = TRUE, full.names = TRUE)[1]
        if (!is.na(src_alt) && file.exists(src_alt)) {
            file.copy(src_alt, f, overwrite = TRUE)
        }
    }
}

# Required input files
chinput_files <- c("GM_rep1.chinput")

for (f in chinput_files) {
    src <- file.path(testDataPath, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback search
        src_alt <- list.files(dataPath, pattern = f, recursive = TRUE, full.names = TRUE)[1]
        if (!is.na(src_alt) && file.exists(src_alt)) {
            file.copy(src_alt, f, overwrite = TRUE)
        }
    }
}