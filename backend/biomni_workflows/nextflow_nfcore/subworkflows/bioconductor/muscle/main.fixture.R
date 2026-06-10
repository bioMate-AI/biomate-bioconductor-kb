library(muscle)
library(Biostrings)

# Locate the example FASTA file referenced in the vignette and ground truth
file_path <- system.file("extdata", "someORF.fa", package = "Biostrings")

# Fallback in case it is shipped directly in the muscle package instead
if (!file.exists(file_path)) {
    file_path <- system.file("extdata", "someORF.fa", package = "muscle")
}

if (file.exists(file_path)) {
    # Read the sequences as done in the vignette
    orf <- readDNAStringSet(file_path, format = "fasta")
    # Serialize to the expected input file name
    writeXStringSet(orf, filepath = "sequences.fasta", format = "fasta")
} else {
    # Fallback to the 'umax' dataset lazy-loaded with the muscle package
    writeXStringSet(umax, filepath = "sequences.fasta", format = "fasta")
}