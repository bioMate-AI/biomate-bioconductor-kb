library(chipenrich)
library(chipenrich.data)

data(peaks_E2F4, package = 'chipenrich.data')
data(peaks_H3K4me3_GM12878, package = 'chipenrich.data')

write.table(peaks_E2F4, file = "peaks_E2F4", sep = "\t", quote = FALSE, row.names = FALSE)
write.table(peaks_H3K4me3_GM12878, file = "peaks_H3K4me3_GM12878", sep = "\t", quote = FALSE, row.names = FALSE)