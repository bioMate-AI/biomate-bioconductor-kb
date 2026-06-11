library(decompTumor2Sig)

extdata_dir <- system.file("extdata", package="decompTumor2Sig")

files_to_copy <- c(
    "Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv",
    "Nik-Zainal_PMID_22608084-pmsignature-sig2.tsv",
    "Nik-Zainal_PMID_22608084-pmsignature-sig3.tsv",
    "Nik-Zainal_PMID_22608084-pmsignature-sig4.tsv",
    "Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata"
)

for (f in files_to_copy) {
    src <- file.path(extdata_dir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        found <- list.files(extdata_dir, pattern = f, recursive = TRUE, full.names = TRUE)
        if (length(found) > 0) {
            file.copy(found[1], f, overwrite = TRUE)
        } else {
            if (grepl("tsv$", f)) {
                mat <- matrix(c(
                    0.05606328, 0.07038910, 0.39331059, 0.13103780, 0.20797476, 0.14122446,
                    0.27758477, 0.21075424, 0.23543226, 0.27622874, 0, 0,
                    0.33081021, 0.25347427, 0.23662536, 0.17909016, 0, 0,
                    0.21472304, 2.6656e-09, 0.55231053, 0.23296643, 0, 0,
                    0.22640542, 0.20024237, 0.32113377, 0.25221844, 0, 0,
                    0.50140066, 0.49859934, 0, 0, 0, 0
                ), nrow=6, byrow=TRUE)
                write.table(mat, f, sep="\t", row.names=FALSE, col.names=FALSE)
            } else if (grepl("Rdata$", f)) {
                dummy_sig <- list()
                save(dummy_sig, file=f)
            }
        }
    }
}