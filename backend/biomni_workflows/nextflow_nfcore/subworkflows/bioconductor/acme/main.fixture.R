library(ACME)

datdir <- system.file('extdata', package='ACME')
all_files <- list.files(datdir, full.names=TRUE)
file.copy(all_files, ".", overwrite = TRUE)

gff_files <- list.files(datdir, pattern="\\.gff$", full.names=TRUE)
if (length(gff_files) > 0) {
    file.copy(gff_files[1], "fnames", overwrite = TRUE)
} else {
    dummy_gff <- data.frame(
        seqname = "chr1",
        source = "nimblegen",
        feature = "probe",
        start = c(10000, 10050),
        end = c(10049, 10099),
        score = c(1.5, 2.0),
        strand = "+",
        frame = ".",
        attribute = c("Probe1", "Probe2")
    )
    write.table(dummy_gff, "fnames", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}