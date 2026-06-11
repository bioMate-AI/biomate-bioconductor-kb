library(ADaCGH2)

# Load the example data provided by the package
data(inputEx, package = "ADaCGH2")

# Write it to the expected input file in the working directory
write.table(inputEx, file = "inputEx.txt", sep = "\t", row.names = FALSE, quote = FALSE)