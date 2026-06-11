library(gdsfmt)
library(SNPRelate)

# The workflow expects a GDS file with sample.annot/pop.group and sample.annot/family.id.
# The package provides an example GDS file that contains exactly these structures.
example_gds <- snpgdsExampleFileName()

# Copy the example GDS file to the working directory as 'genofile'
file.copy(example_gds, "genofile", overwrite = TRUE)

# Guarantee the declared input file exists
if (!file.exists("genofile")) {
    stop("Failed to create 'genofile'")
}