library(sangerseqR)

ab1_src <- system.file("extdata", "heterozygous.ab1", package = "sangerseqR")
scf_src <- system.file("extdata", "homozygous.scf", package = "sangerseqR")

if (file.exists(ab1_src)) {
    file.copy(ab1_src, "heterozygous.ab1", overwrite = TRUE)
} else {
    stop("heterozygous.ab1 not found in sangerseqR extdata")
}

if (file.exists(scf_src)) {
    file.copy(scf_src, "homozygous.scf", overwrite = TRUE)
} else {
    stop("homozygous.scf not found in sangerseqR extdata")
}