# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pathview")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(pathview)

# Load required datasets for ID types
data(cpd.simtypes)
data(gene.idtype.list)

# Generate simulated metabolite data with CAS IDs
set.seed(123)
cpd.cas <- sim.mol.data(mol.type = "cpd", id.type = cpd.simtypes[2], nmol = 10000)

# Generate simulated gene data with Ensembl Protein IDs
gene.ensprot <- sim.mol.data(mol.type = "gene", id.type = gene.idtype.list[4], nmol = 50000)

# Serialize to TSV files
write.table(data.frame(Expression = gene.ensprot), 
            file = "ensembl_gene_expression.tsv", 
            sep = "\t", 
            row.names = TRUE, 
            col.names = NA, 
            quote = FALSE)

write.table(data.frame(Abundance = cpd.cas), 
            file = "cas_metabolite_abundance.tsv", 
            sep = "\t", 
            row.names = TRUE, 
            col.names = NA, 
            quote = FALSE)