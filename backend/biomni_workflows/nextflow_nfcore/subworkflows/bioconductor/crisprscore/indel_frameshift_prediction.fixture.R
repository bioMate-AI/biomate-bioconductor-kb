library(crisprScore)

user_seq_file <- list.files(system.file("extdata", package="crisprScore"), pattern="user_sequences.txt", recursive=TRUE, full.names=TRUE)

if (length(user_seq_file) > 0 && file.exists(user_seq_file[1])) {
    file.copy(user_seq_file[1], "sequences.txt")
} else {
    # Construct synthetic 65bp sequences
    # 13bp upstream + 20bp spacer + 3bp PAM + 29bp downstream
    upstream <- "ATCGATCGATCGA" 
    spacer <- "ATCGATGCTGATGCTAGATA" 
    pam <- "AGG" 
    downstream <- "ATCGATCGATCGATCGATCGATCGATCGA" 
    
    seq1 <- paste0(upstream, spacer, pam, downstream)
    seq2 <- paste0("GCTAGCTAGCTAG", "GCTAGCTAGCTAGCTAGCTA", "CGG", "GCTAGCTAGCTAGCTAGCTAGCTAGCTAG")
    
    writeLines(c(seq1, seq2), "sequences.txt")
}