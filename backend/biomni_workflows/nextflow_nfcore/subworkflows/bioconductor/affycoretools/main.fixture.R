# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("affycoretools", "Biobase", "AnnotationDbi", "hgu95av2.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library(affycoretools))
suppressMessages(library(Biobase)) # Required for ExpressionSet class definition
suppressMessages(library(AnnotationDbi)) # Required for AnnotationDbi::dbfile
suppressMessages(library(hgu95av2.db)) # Required to access the hgu95av2.db AnnotationDb object

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the sample ExpressionSet object as described in the vignette.
data(sample.ExpressionSet)
eset <- sample.ExpressionSet

# 2. Serialize the objects to EACH declared input file in the EXACT format the workflow reads.

# For 'eset': The workflow reads 'eset.rds' using readRDS().
# Save the 'eset' object (which is an ExpressionSet) to "eset.rds".
saveRDS(eset, "eset.rds")

# For 'hgu95av2.db': The workflow reads "hgu95av2.db" using AnnotationDbi::loadDb().
# This means "hgu95av2.db" must be the SQLite database file itself.
# The hgu95av2.db package, when loaded, provides an AnnotationDb object named hgu95av2.db.
# We can extract the path to its underlying SQLite file using AnnotationDbi::dbfile().
db_file_path <- AnnotationDbi::dbfile(hgu95av2.db)

# Copy this SQLite database file to the current working directory, naming it "hgu95av2.db".
file.copy(db_file_path, "hgu95av2.db", overwrite = TRUE)