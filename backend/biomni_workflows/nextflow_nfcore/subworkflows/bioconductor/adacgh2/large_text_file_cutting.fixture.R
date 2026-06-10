library(ADaCGH2)

# Load the example dataset provided by the package
data(inputEx, package = "ADaCGH2")

# Serialize the data frame to a tab-delimited text file as expected by the workflow
write.table(
    inputEx, 
    file = "inputEx.txt", 
    sep = "\t", 
    row.names = FALSE, 
    quote = FALSE
)