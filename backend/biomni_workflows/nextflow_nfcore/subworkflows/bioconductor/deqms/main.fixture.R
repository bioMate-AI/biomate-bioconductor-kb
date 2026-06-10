# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DEqMS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DEqMS)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code to materialize the example object.
# The vignette's data preparation for "miR_Proteintable.txt" involves downloading it from a URL.
# To adhere to the "fully OFFLINE" constraint, we use the equivalent example data
# shipped with the `deqms` package itself. The file "example_protein_table.txt"
# in the package's `extdata` directory has the same structure and content as the
# downloaded "miR_Proteintable.txt" used in the vignette's first workflow example.

# Get the file path to the example protein table within the installed `deqms` package.
example_protein_table_path <- system.file("extdata", "example_protein_table.txt", package = "DEqMS")

# Read the content of the example protein table.
# The parameters for read.table are chosen to match how the vignette's workflow
# would read "miR_Proteintable.txt".
df.prot_content <- read.table(
    example_protein_table_path,
    stringsAsFactors = FALSE,
    header = TRUE,
    quote = "",
    comment.char = "",
    sep = "\t"
)

# 2. Serialize that object to the declared input file (miR_Proteintable.txt)
# in the EXACT format the workflow reads.
# The workflow expects a file named "miR_Proteintable.txt" in the working directory.
# We write the `df.prot_content` data frame to this file, ensuring the output
# format (separator, headers, quoting, row names) matches the `read.table`
# call used by the workflow.
write.table(
    df.prot_content,
    "miR_Proteintable.txt",
    sep = "\t",
    row.names = FALSE, # Prevent writing R's row names as a column in the file
    quote = FALSE,     # Prevent quoting of character fields, matching quote = "" in read.table
    col.names = TRUE   # Write column names as the header, matching header = TRUE in read.table
)