library(LedPred)

dirPath <- system.file("extdata", package="LedPred")
file.list <- list.files(dirPath, full.names=TRUE)

# background.freq
bg_file <- file.list[grep("freq", file.list)][1]
if (!is.na(bg_file) && file.exists(bg_file)) {
    file.copy(bg_file, "background.freq", overwrite = TRUE)
} else {
    writeLines(c("A 0.25", "C 0.25", "G 0.25", "T 0.25"), "background.freq")
}

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

# TF.matrices
tf_file <- file.list[grep("tf", file.list)][1]
if (is.na(tf_file)) tf_file <- file.list[grep("matrices", file.list)][1]
if (!is.na(tf_file) && file.exists(tf_file)) {
    file.copy(tf_file, "TF.matrices", overwrite = TRUE)
} else {
    writeLines(c(">MA0001.1", "A [ 1 2 3 4 ]", "C [ 1 2 3 4 ]", "G [ 1 2 3 4 ]", "T [ 1 2 3 4 ]"), "TF.matrices")
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
ngs_files_list <- list.files(ngs.path, full.names=TRUE)
if (length(ngs_files_list) > 0) {
    file.copy(ngs_files_list[1], "ngs.files", overwrite = TRUE)
} else {
    writeLines(c("chr1\t150\t160\tpeak1\t10"), "ngs.files")
}