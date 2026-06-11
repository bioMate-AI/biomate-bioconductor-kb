library(specL)

# Copy the shipped SQLite database to the working directory
file.copy(
  from = system.file("extdata", "peptideStd.sqlite", package = "specL"),
  to = "peptideStd.sqlite",
  overwrite = TRUE
)

# Copy the shipped FASTA file to the working directory
file.copy(
  from = system.file("extdata", "SP201602-specL.fasta.gz", package = "specL"),
  to = "SP201602-specL.fasta.gz",
  overwrite = TRUE
)