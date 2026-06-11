library("pRoloc")
library("pRolocdata")

# Load the primary and auxiliary datasets from the companion data package
data("andy2011")
data("andy2011goCC")

# Extract the quantitative spatial proteomics data (primary) and binary GO terms (auxiliary)
primary_matrix <- exprs(andy2011)
auxiliary_matrix <- exprs(andy2011goCC)

# Write to CSV files exactly as expected by the workflow
write.csv(primary_matrix, file = "primary_data.csv", row.names = TRUE)
write.csv(auxiliary_matrix, file = "auxiliary_data.csv", row.names = TRUE)