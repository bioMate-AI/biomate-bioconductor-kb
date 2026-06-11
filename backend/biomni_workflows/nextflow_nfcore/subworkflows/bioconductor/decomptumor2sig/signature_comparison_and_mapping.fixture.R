library(decompTumor2Sig)

extdata_dir <- system.file("extdata", package="decompTumor2Sig")

# 1. Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv
f1 <- list.files(extdata_dir, pattern="Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv", full.names=TRUE, recursive=TRUE)
if (length(f1) > 0) {
    file.copy(f1[1], "Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv", overwrite=TRUE)
} else {
    # Fallback: create a synthetic Shiraishi signature file matching the vignette example
    lines <- c(
        "0.05606328 0.07038910 0.39331059 0.13103780 0.20797476 0.14122446",
        "0.27758477 0.21075424 0.23543226 0.27622874 0 0",
        "0.33081021 0.25347427 0.23662536 0.17909016 0 0",
        "0.21472304 2.6656e-09 0.55231053 0.23296643 0 0",
        "0.22640542 0.20024237 0.32113377 0.25221844 0 0",
        "0.50140066 0.49859934 0 0 0 0"
    )
    writeLines(lines, "Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv")
}

# 2. Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata
f2 <- list.files(extdata_dir, pattern="Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata", full.names=TRUE, recursive=TRUE)
if (length(f2) > 0) {
    file.copy(f2[1], "Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata", overwrite=TRUE)
} else {
    # Fallback: create a dummy Rdata file
    dummy_sig <- list()
    save(dummy_sig, file="Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata")
}