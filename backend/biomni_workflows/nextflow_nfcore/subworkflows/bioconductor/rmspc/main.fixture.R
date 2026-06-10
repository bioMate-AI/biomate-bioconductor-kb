library(rmspc)

path <- system.file("extdata", package = "rmspc")
input1 <- file.path(path, "rep1.bed")
input2 <- file.path(path, "rep2.bed")

if (file.exists(input1)) {
    file.copy(input1, "rep1.bed", overwrite = TRUE)
} else {
    writeLines(c("chr1\t10000\t10039\tMACS_peak_1\t2.42", 
                 "chr1\t10102\t10190\tMACS_peak_2\t3.23"), "rep1.bed")
}

if (file.exists(input2)) {
    file.copy(input2, "rep2.bed", overwrite = TRUE)
} else {
    writeLines(c("chr1\t10000\t10039\tMACS_peak_1\t2.42", 
                 "chr1\t10102\t10190\tMACS_peak_2\t3.23"), "rep2.bed")
}