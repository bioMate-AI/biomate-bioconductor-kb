library(cosmiq)
library(faahKO)

cdfpath <- file.path(find.package("faahKO"), "cdf")
original_files <- dir(c(paste(cdfpath, "WT", sep='/'), 
                        paste(cdfpath, "KO", sep='/')), full.names=TRUE)

# Copy the raw LCMS/GCMS files to the working directory as expected by the workflow
file.copy(original_files, ".", overwrite = TRUE)

# Define the input files vector
my.input.files <- basename(original_files)