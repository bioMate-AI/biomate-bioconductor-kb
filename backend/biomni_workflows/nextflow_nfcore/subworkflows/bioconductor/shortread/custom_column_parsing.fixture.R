library(ShortRead)

row1 <- c("HWI-EAS88", "3", "2", "1", "451", "945", "", "", 
          "CCAGAGCCCCCCGCTCACTCCTGAACCAGTCTCTC", "YQMIMIMMLMMIGIGMFICMFFFIMMHIIHAAGAH", 
          "NM", "", "", "", "", "", "", "", "", "", "")

row2 <- c("HWI-EAS88", "3", "2", "1", "451", "946", "", "", 
          "AGCCTCCCTCTTTCTGAATATACGGCAGAGCTGTT", "ZXZUYXZQYYXUZXYZYYZZXXZZIMFHXQSUPPO", 
          "NM", "", "", "", "", "", "", "", "", "", "")

export_data <- rbind(row1, row2)

write.table(export_data, file="export_file.txt", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)