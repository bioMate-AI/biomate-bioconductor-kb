library(crisprScore)

flank5 <- "ACCG" #4bp
pam <- "TTTT" #4bp
spacer <- "AATCGATGCTGATGCTAGATATT" #23bp
flank3 <- "AAG" #3bp
input1 <- paste0(flank5, pam, spacer, flank3)

input2 <- "ACCGTTTTAATCGATGCTGATGCTAGATATTAAG"
input3 <- "ACCGTTTTAATCGATGCTGATGCTAGATATTCAG"

writeLines(c(input1, input2, input3), "user_sequences.txt")