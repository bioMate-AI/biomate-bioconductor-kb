library(DiffLogo)
library(MotifDb)

# 1. Reproduce the vignette's data-preparation code
hitIndeces = grep('CTCF', values(MotifDb)$geneSymbol, ignore.case=TRUE)
motif_list = as.list(MotifDb[hitIndeces])

# Extract the exact motifs used in the vignette
pwm_long = reverseComplement(motif_list$"Hsapiens-JASPAR_CORE-CTCF-MA0139.1")
pwm_short = motif_list$"Hsapiens-jolma2013-CTCF"

# 2. Serialize the objects to the declared input files
# DiffLogo's getPwmFromPwmFile() reads tables where the first column can be the row names (A, C, G, T)
write.table(pwm_long, "pwm_long.pwm", sep="\t", quote=FALSE, col.names=FALSE, row.names=TRUE)
write.table(pwm_short, "pwm_short.pwm", sep="\t", quote=FALSE, col.names=FALSE, row.names=TRUE)