library(rGenomeTracks)

tads_src <- system.file("extdata", "tad_classification.bed", package = "rGenomeTracks")
if (file.exists(tads_src)) {
    file.copy(tads_src, "tad_classification.bed", overwrite = TRUE)
} else {
    writeLines(c("chrX\t2500000\t3000000\tTAD1"), "tad_classification.bed")
}

arcs_src <- system.file("extdata", "links2.links", package = "rGenomeTracks")
if (file.exists(arcs_src)) {
    file.copy(arcs_src, "links2.links", overwrite = TRUE)
} else {
    writeLines(c("chrX\t2500000\t2600000\tchrX\t2800000\t2900000\t0.5"), "links2.links")
}

bw_src <- system.file("extdata", "bigwig2_X_2.5e6_3.5e6.bw", package = "rGenomeTracks")
if (file.exists(bw_src)) {
    file.copy(bw_src, "bigwig2_X_2.5e6_3.5e6.bw", overwrite = TRUE)
} else {
    file.create("bigwig2_X_2.5e6_3.5e6.bw")
}

if (!file.exists("h5_dir")) {
    if (requireNamespace("rhdf5", quietly = TRUE)) {
        rhdf5::h5createFile("h5_dir")
    } else {
        file.create("h5_dir")
    }
}