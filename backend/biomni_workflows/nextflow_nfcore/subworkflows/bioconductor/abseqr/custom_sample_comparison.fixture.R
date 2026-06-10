library(abseqR)

exdata <- system.file("extdata", "ex", package = "abseqR")

# The workflow expects these directories in the working directory
input_dirs <- c("dataPath", "SRR_CTRL", "SRR_EXP")

for (d in input_dirs) {
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
    files_to_copy <- list.files(exdata, full.names = TRUE)
    file.copy(files_to_copy, d, recursive = TRUE)
}