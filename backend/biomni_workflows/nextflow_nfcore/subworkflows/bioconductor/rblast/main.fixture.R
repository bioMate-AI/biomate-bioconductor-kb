library(rBLAST)
library(Biostrings)

# 1. Create RNA_example.fasta
# Read the example FASTA file shipped with the package
fasta_file <- system.file("examples/RNA_example.fasta", package = "rBLAST")

if (fasta_file != "" && file.exists(fasta_file)) {
    seq <- readRNAStringSet(fasta_file)
} else {
    # Fallback synthetic data if the package file is missing
    seq <- RNAStringSet(c(
        "AB015560.1" = "AGAGUUUGAUCCUGGCUCAGAACGGUGAAGUCGUAACAAGGUAACC",
        "D14432.1" = "GCUGGCGGCAGGCCUAACACAUGCACGGUAAGGUCAGCGACUGGGG"
    ))
}
writeXStringSet(seq, filepath = "RNA_example.fasta")

# 2. Create 16S_ribosomal_RNA.tar.gz
# We need to mock the 16S Microbial rRNA database archive.
# If BLAST+ is installed, we can create a real database from the example sequences.
# Otherwise, we create dummy files to ensure the archive exists.
if (Sys.which("makeblastdb") != "") {
    writeXStringSet(seq, filepath = "temp_seqs.fasta")
    makeblastdb("temp_seqs.fasta", db_name = "16S_ribosomal_RNA", dbtype = "nucl")
    
    # Find the generated database files (e.g., .nhr, .nin, .nsq)
    db_files <- list.files(".", pattern = "^16S_ribosomal_RNA\\.")
    tar("16S_ribosomal_RNA.tar.gz", files = db_files, compression = "gzip")
    
    # Clean up temporary files
    unlink("temp_seqs.fasta")
    unlink(db_files)
} else {
    # Create dummy files if BLAST is not installed
    dummy_files <- paste0("16S_ribosomal_RNA.", c("nhr", "nin", "nsq"))
    for (f in dummy_files) {
        writeLines("dummy database content", f)
    }
    tar("16S_ribosomal_RNA.tar.gz", files = dummy_files, compression = "gzip")
    unlink(dummy_files)
}