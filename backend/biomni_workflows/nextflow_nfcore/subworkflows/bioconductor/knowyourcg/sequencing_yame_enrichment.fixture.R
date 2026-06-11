library(knowYourCG)

# input_cpgs.bed
bed_candidates <- list.files(system.file("extdata", package="knowYourCG"), pattern="input_cpgs\\.bed$", full.names=TRUE, recursive=TRUE)
if (length(bed_candidates) > 0 && file.exists(bed_candidates[1])) {
    file.copy(bed_candidates[1], "input_cpgs.bed", overwrite=TRUE)
} else {
    bed_data <- data.frame(
        chr = c("chr1", "chr1", "chr2"),
        start = c(10468, 10470, 10483),
        end = c(10469, 10471, 10484)
    )
    write.table(bed_data, "input_cpgs.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}

# cpg_nocontig.cr
cr_candidates <- list.files(system.file("extdata", package="knowYourCG"), pattern="cpg_nocontig\\.cr$", full.names=TRUE, recursive=TRUE)
if (length(cr_candidates) > 0 && file.exists(cr_candidates[1])) {
    file.copy(cr_candidates[1], "cpg_nocontig.cr", overwrite=TRUE)
} else {
    cr_data <- data.frame(
        chr = c("chr1", "chr1", "chr2"),
        start = c(10468, 10470, 10483),
        end = c(10469, 10471, 10484)
    )
    write.table(cr_data, "cpg_nocontig.cr", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}