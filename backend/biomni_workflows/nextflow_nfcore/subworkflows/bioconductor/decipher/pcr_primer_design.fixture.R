library(DECIPHER)
library(RSQLite)
library(Biostrings)

# Create 'fas' input
fas_source <- system.file("extdata", "Bacteria_175seqs.fas", package="DECIPHER")
if (file.exists(fas_source)) {
    file.copy(fas_source, "fas")
} else {
    # Fallback if the exact file is not shipped
    seqs <- DNAStringSet(c("ATGC", "ATGG"))
    names(seqs) <- c("seq1", "seq2")
    writeXStringSet(seqs, "fas")
}

# Create 'dbConn' input
gb_source <- system.file("extdata", "Bacteria_175seqs.gen", package="DECIPHER")
db <- dbConnect(dbDriver("SQLite"), "dbConn")
if (file.exists(gb_source)) {
    Seqs2DB(gb_source, "GenBank", db, "Bacteria")
} else {
    # Fallback if the exact file is not shipped
    seqs <- DNAStringSet(c("ATGC", "ATGG"))
    names(seqs) <- c("seq1", "seq2")
    fas_temp <- tempfile(fileext=".fas")
    writeXStringSet(seqs, fas_temp)
    Seqs2DB(fas_temp, "FASTA", db, "Bacteria")
}
dbDisconnect(db)