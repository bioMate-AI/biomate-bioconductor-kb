library(puma)
library(pumadata)

# Create SampleNameTable as expected by igmoExon
sample_info <- data.frame(
  Celnames = c("C0006.CEL", "C021.CEL", "F023_NEG.CEL", "F043_NEG.CEL"),
  Condition = c("Yes", "Yes", "No", "No")
)
write.table(sample_info, file="SampleNameTable", sep="\t", row.names=FALSE, quote=FALSE)

# Create dummy CEL files to satisfy file existence checks
exonFilenames <- sample_info$Celnames
for (f in exonFilenames) {
  writeLines("[CEL]\nVersion=4\n", f)
}

# In case the workflow literally attempts to read a file named "exonFilenames"
writeLines(exonFilenames, "exonFilenames")