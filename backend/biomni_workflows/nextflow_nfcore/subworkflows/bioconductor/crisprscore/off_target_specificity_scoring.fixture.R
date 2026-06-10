library(crisprScore)

spacer <- c("ATCGATGCTGATGCTAGATA", "ATCGATGCTGATGCTAGATA")
protospacer <- c("ATCGATGCTGATGCTAGATA", "ATCGATGCTGATGCTAGATT")
pam <- c("AGG", "AGG")

df <- data.frame(
    spacer = spacer,
    protospacer = protospacer,
    pam = pam,
    stringsAsFactors = FALSE
)

write.csv(df, "gRNAs_and_targets.csv", row.names = FALSE)