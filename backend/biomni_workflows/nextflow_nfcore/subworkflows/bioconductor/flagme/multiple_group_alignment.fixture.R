require(gcspikelite)
library(flagme)

gcmsPath <- paste(find.package("gcspikelite"), "data", sep="/")
data(targets)
cdfFiles_paths <- paste(gcmsPath, targets$FileName, sep="/")
eluFiles_paths <- gsub("CDF", "ELU", cdfFiles_paths)

# Copy the actual data files to the working directory
file.copy(cdfFiles_paths, basename(cdfFiles_paths))
file.copy(eluFiles_paths, basename(eluFiles_paths))

# Write the targets data frame to a CSV file as expected by the workflow
write.csv(targets, "targets", row.names = FALSE)

# In case the workflow expects files literally named 'cdfFiles' and 'eluFiles' containing the filenames
writeLines(basename(cdfFiles_paths), "cdfFiles")
writeLines(basename(eluFiles_paths), "eluFiles")