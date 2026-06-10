# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("NOISeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(NOISeq)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the example data from the NOISeq package
data(Marioni)

# Define myfactors as in vignette chunk 4
myfactors <- data.frame(Tissue=c("Kidney","Liver","Kidney","Liver","Liver","Kidney","Liver",
                                 "Kidney","Liver","Kidney"),
                        TissueRun = c("Kidney_1","Liver_1","Kidney_1","Liver_1","Liver_1",
                                      "Kidney_1","Liver_1","Kidney_2","Liver_2","Kidney_2"),
                        Run = c(rep("R1", 7), rep("R2", 3)))
# Ensure row names for myfactors match the sample names in mycounts
# The vignette's myfactors does not explicitly set row names, but the readData function
# expects factors to have row names corresponding to sample names.
# Let's assume the order matches the columns of mycounts.
# From vignette chunk 6, mydata is created with mycounts and myfactors.
# The column names of mycounts are the sample IDs.
# The number of rows in myfactors (10) matches the number of columns in mycounts (10).
# We need to set the row names of myfactors to match the column names of mycounts.
colnames_mycounts <- colnames(mycounts)
if (length(colnames_mycounts) == nrow(myfactors)) {
  rownames(myfactors) <- colnames_mycounts
} else {
  stop("Number of samples in mycounts does not match number of rows in myfactors.")
}


# The workflow reads 'annotations.csv' which is then used to provide 'length', 'gc', 'biotype', 'chromosome'
# to the readData function. These correspond to mylength, mygc, mybiotypes, mychroms from the vignette.
# We need to combine these into a single data frame for 'annotations.csv'.
# Ensure all these objects have consistent row names (gene IDs).
# mylength and mygc are named vectors, convert them to data frames first.
annotations_df <- data.frame(
  length = mylength,
  gc = mygc,
  mybiotypes, # This is already a data frame with 'biotype' column
  mychroms    # This is already a data frame with 'chromosome' column
)

# Ensure row names are set for the combined annotations_df
# The names of mylength/mygc are the gene IDs, which should match rownames of mybiotypes/mychroms.
# cbind should preserve these if they are consistent.
if (!all(rownames(annotations_df) == rownames(mycounts))) {
  stop("Row names of annotations_df do not match row names of mycounts.")
}


# 2. Serialize objects to declared input files
# Write mycounts to count_matrix.csv
write.csv(mycounts, file = "count_matrix.csv", row.names = TRUE, quote = FALSE)

# Write myfactors to factors.csv
write.csv(myfactors, file = "factors.csv", row.names = TRUE, quote = TRUE)

# Write combined annotations to annotations.csv
write.csv(annotations_df, file = "annotations.csv", row.names = TRUE, quote = TRUE)
