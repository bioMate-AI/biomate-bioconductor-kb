library(HMMcopy)

tfile <- system.file("extdata", "tumour.wig", package = "HMMcopy")
gfile <- system.file("extdata", "gc.wig", package = "HMMcopy")
mfile <- system.file("extdata", "map.wig", package = "HMMcopy")

if (file.exists(tfile)) {
    file.copy(tfile, "tumour.wig", overwrite = TRUE)
} else {
    stop("tumour.wig not found in HMMcopy extdata")
}

if (file.exists(gfile)) {
    file.copy(gfile, "gc.wig", overwrite = TRUE)
} else {
    stop("gc.wig not found in HMMcopy extdata")
}

if (file.exists(mfile)) {
    file.copy(mfile, "map.wig", overwrite = TRUE)
} else {
    stop("map.wig not found in HMMcopy extdata")
}