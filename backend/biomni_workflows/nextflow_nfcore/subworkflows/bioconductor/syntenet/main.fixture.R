library(syntenet)

# Locate and copy the example FASTA files shipped with the package
fasta_dir <- system.file("extdata", "sequences", package = "syntenet")
fasta_files <- list.files(fasta_dir, full.names = TRUE)
for (f in fasta_files) {
    file.copy(f, basename(f), overwrite = TRUE)
}

# Locate and copy the example GFF3 files shipped with the package
gff_dir <- system.file("extdata", "annotation", package = "syntenet")
gff_files <- list.files(gff_dir, full.names = TRUE)
for (f in gff_files) {
    file.copy(f, basename(f), overwrite = TRUE)
}

# Load the example data objects as demonstrated in the vignette
data(proteomes)
data(annotation)