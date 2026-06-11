library(LedPred)

dirPath <- system.file("extdata", package="LedPred")
file.list <- list.files(dirPath, full.names=TRUE)

# positive.bed
pos_file <- file.list[grep("positive", file.list)][1]
if (!is.na(pos_file) && file.exists(pos_file)) {
    file.copy(pos_file, "positive.bed", overwrite = TRUE)
} else {
    writeLines(c("chr1\t100\t200", "chr1\t300\t400"), "positive.bed")
}

# negative.bed
neg_file <- file.list[grep("negative", file.list)][1]
if (!is.na(neg_file) && file.exists(neg_file)) {
    file.copy(neg_file, "negative.bed", overwrite = TRUE)
} else {
    writeLines(c("chr1\t500\t600", "chr1\t700\t800"), "negative.bed")
}

# background.freq
freq_file <- file.list[grep("freq", file.list)][1]
if (!is.na(freq_file) && file.exists(freq_file)) {
    file.copy(freq_file, "background.freq", overwrite = TRUE)
} else {
    writeLines(c("A 0.25", "C 0.25", "G 0.25", "T 0.25"), "background.freq")
}

# TF.matrices
tf_file <- file.list[grep("tf|259_matrices", file.list)][1]
if (!is.na(tf_file) && file.exists(tf_file)) {
    file.copy(tf_file, "TF.matrices", overwrite = TRUE)
} else {
    writeLines(c("NA matrix1", "01 02 03 04"), "TF.matrices")
}

# prediction_small.bed
pred_file <- file.list[grep("prediction_small", file.list)][1]
if (!is.na(pred_file) && file.exists(pred_file)) {
    file.copy(pred_file, "prediction_small.bed", overwrite = TRUE)
} else {
    writeLines(c("chr1\t1000\t1100"), "prediction_small.bed")
}

# ngs.files
ngs.path <- system.file("extdata/ngs", package="LedPred")
ngs_file_list <- list.files(ngs.path, full.names=TRUE)
if (length(ngs_file_list) > 0 && file.exists(ngs_file_list[1])) {
    file.copy(ngs_file_list[1], "ngs.files", overwrite = TRUE)
} else {
    writeLines(c("chr1\t100\t200\tpeak1\t10"), "ngs.files")
}