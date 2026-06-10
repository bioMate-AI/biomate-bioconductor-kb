library(DiffLogo)
library(MotifDb)

# Import motifs from MotifDb as shown in the vignette
hitIndeces = grep('CTCF', values(MotifDb)$geneSymbol, ignore.case=TRUE)
motif_list = as.list(MotifDb[hitIndeces])

# Extract and prepare the specific PWMs
pwm_long = reverseComplement(motif_list$"Hsapiens-JASPAR_CORE-CTCF-MA0139.1")
pwm_short = motif_list$"Hsapiens-jolma2013-CTCF"

# Serialize the PWM matrices to the expected .pwm files
# DiffLogo's getPwmFromPwmFile expects a table where rows are nucleotides (A, C, G, T)
# and columns are positions. If the first column is character, it uses it as row names.
write.table(pwm_long, file="pwm_long.pwm", sep="\t", quote=FALSE, col.names=FALSE, row.names=TRUE)
write.table(pwm_short, file="pwm_short.pwm", sep="\t", quote=FALSE, col.names=FALSE, row.names=TRUE)