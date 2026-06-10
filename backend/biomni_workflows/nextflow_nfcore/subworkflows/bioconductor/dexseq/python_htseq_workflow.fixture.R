library(DEXSeq)
library(pasilla)

# Locate the pasilla extdata directory which contains the raw count files and GFF
inDir <- system.file("extdata", package="pasilla")

# 1. count_files
# The workflow expects text files containing exon counts per sample.
# We copy them to a 'count_files' directory and the current directory to ensure they are found.
countFiles <- list.files(inDir, pattern="fb.txt$", full.names=TRUE)
dir.create("count_files", showWarnings = FALSE)
file.copy(countFiles, file.path("count_files", basename(countFiles)), overwrite = TRUE)
file.copy(countFiles, basename(countFiles), overwrite = TRUE)

# 2. flattened.gff
# The workflow expects a collapsed exon counting bins GFF file named 'flattened.gff'
flattenedFile <- list.files(inDir, pattern="gff$", full.names=TRUE)[1]
file.copy(flattenedFile, "flattened.gff", overwrite = TRUE)

# 3. sample_table.csv
# The workflow reads: sampleTable = read.csv("sample_table.csv", row.names = 1, stringsAsFactors = TRUE)
sample_names <- sub(".txt$", "", basename(countFiles))
condition <- ifelse(grepl("untreated", sample_names), "untreated", "treated")
type <- ifelse(sample_names %in% c("treated1fb", "untreated1fb", "untreated2fb"), "single-read", "paired-end")

sampleTable <- data.frame(
    row.names = sample_names,
    condition = condition,
    type = type,
    fileName = basename(countFiles)
)

write.csv(sampleTable, "sample_table.csv", quote = FALSE)