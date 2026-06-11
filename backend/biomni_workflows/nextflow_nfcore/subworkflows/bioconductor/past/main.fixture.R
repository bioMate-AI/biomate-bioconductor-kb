library(PAST)

extdata_dir <- system.file("extdata", package = "PAST")

get_file <- function(base_pattern) {
    files <- list.files(extdata_dir, pattern = base_pattern, full.names = TRUE, ignore.case = TRUE)
    if (length(files) > 0) {
        return(files[1])
    }
    return(NA)
}

assoc_in <- get_file("association\\.txt")
eff_in <- get_file("effects\\.txt")
ld_in <- get_file("LD\\.txt")
genes_in <- get_file("genes\\.gff")
path_in <- get_file("pathways\\.txt")

write_xz_file <- function(in_file, out_file, dummy_content) {
    con <- xzfile(out_file, "w")
    if (!is.na(in_file) && file.exists(in_file)) {
        writeLines(suppressWarnings(readLines(in_file)), con)
    } else {
        writeLines(dummy_content, con)
    }
    close(con)
}

write_plain_file <- function(in_file, out_file, dummy_content) {
    if (!is.na(in_file) && file.exists(in_file)) {
        writeLines(suppressWarnings(readLines(in_file)), out_file)
    } else {
        writeLines(dummy_content, out_file)
    }
}

# Dummy contents in case the package files are missing
dummy_assoc <- c("Trait\tMarker\tChr\tPos\tp\tR2", "Trait1\tM1\t1\t100\t0.01\t0.1")
dummy_eff <- c("Trait\tMarker\tAllele\tEffect", "Trait1\tM1\tA\t0.5")
dummy_ld <- c("Locus1\tLocus2\tR^2", "M1\tM2\t0.9")
dummy_genes <- c("1\tPAST\tgene\t1\t1000\t.\t+\t.\tID=gene1")
dummy_path <- c("PWY1\tPathway 1\tgene1")

write_xz_file(assoc_in, "association.txt.xz", dummy_assoc)
write_xz_file(eff_in, "effects.txt.xz", dummy_eff)
write_xz_file(ld_in, "LD.txt.xz", dummy_ld)
write_xz_file(path_in, "pathways.txt.xz", dummy_path)
write_plain_file(genes_in, "genes.gff", dummy_genes)