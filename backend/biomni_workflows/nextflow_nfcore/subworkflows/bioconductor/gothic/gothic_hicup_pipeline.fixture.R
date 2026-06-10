suppressPackageStartupMessages({
  library(GOTHiC)
  library(HiCDataLymphoblast)
})

dirPath <- system.file("extdata", package = "HiCDataLymphoblast")
all_files <- list.files(dirPath, full.names = TRUE)

if (length(all_files) >= 4) {
  # The vignette uses the 4th file for fileName and 3rd for restrictionFile
  file.copy(all_files[4], "fileName", overwrite = TRUE)
  file.copy(all_files[3], "restrictionFile", overwrite = TRUE)
} else {
  # Fallback synthetic files if the package contents changed
  
  # HiCUP mapped and filtered reads format
  hicup_data <- data.frame(
    Read_1 = c("read1", "read2"),
    Flag_1 = c(0, 0),
    Chromosome_1 = c("chr20", "chr20"),
    Position_1 = c(1000, 2000),
    MapQ_1 = c(30, 30),
    Cigar_1 = c("50M", "50M"),
    Read_2 = c("read1", "read2"),
    Flag_2 = c(0, 0),
    Chromosome_2 = c("chr20", "chr20"),
    Position_2 = c(5000, 6000),
    MapQ_2 = c(30, 30),
    Cigar_2 = c("50M", "50M")
  )
  write.table(hicup_data, "fileName", sep = "\t", row.names = FALSE, quote = FALSE)
  
  # Restriction file format
  res_data <- data.frame(
    Chromosome = c("chr20", "chr20"),
    Fragment_Start = c(1, 4000),
    Fragment_End = c(3999, 8000),
    Size = c(3999, 4001)
  )
  write.table(res_data, "restrictionFile", sep = "\t", row.names = FALSE, quote = FALSE)
}