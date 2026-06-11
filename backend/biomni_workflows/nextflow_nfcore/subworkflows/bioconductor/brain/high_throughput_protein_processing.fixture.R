# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BRAIN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BRAIN)

# The workflow reads 'uniprot.tab' from the working directory.
# The vignette (chunks 9-11, eval=FALSE) describes how 'uniprot.tab' is read
# and processed to generate 'uniprotBRAIN.txt'.
# Specifically, 'uniprot.tab' is read as a tab-separated file with a header,
# and it must contain a 'Sequence' column with amino acid sequences.
# The vignette itself does not provide 'uniprot.tab' as a reproducible dataset
# (e.g., via data() or system.file()).
# Therefore, to create this input file as a test fixture, we must construct
# a minimal, valid 'uniprot.tab' that adheres to the described format.

# We will create a data frame with a 'Sequence' column, using simple amino acid
# sequences. The 'AMINOS' list in vignette chunk 10 provides a canonical set
# of amino acids, which we can use as building blocks to minimize "invention".
# We also add a 'Description' column to make the file structure more realistic,
# though only 'Sequence' is explicitly used by the vignette's processing code.
uniprot_sequences <- data.frame(
  Sequence = c("A", "R", "N", "D", "CYS"), # Single amino acids and a short peptide
  Description = c("Alanine", "Arginine", "Asparagine", "Aspartic Acid", "Cysteine-Serine"),
  stringsAsFactors = FALSE
)

# Write the data frame to 'uniprot.tab' in the format expected by the workflow:
# tab-separated, with a header, and no row names.
# quote=FALSE is used to prevent R from adding quotes around character strings,
# which is typical for simple tab-separated files.
write.table(uniprot_sequences, "uniprot.tab", sep = "\t", row.names = FALSE, quote = FALSE, header = TRUE)