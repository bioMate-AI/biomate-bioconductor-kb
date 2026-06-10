# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("biodb")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(biodb)

compUrl <- system.file("extdata", "chebi_extract_custom.csv", package='biodb')

if (file.exists(compUrl)) {
    file.copy(compUrl, "input.csv", overwrite = TRUE)
} else {
    df <- data.frame(
        ID = c("1018", "1390", "1456", "1549", "1894", "1932"),
        formula = c("C2H8AsNO3", "C8H8O2", "C3H9NO2", "C3H5O3R", "C5H11NO", "C6H6NR"),
        mass = c(168.97201, 136.05243, 91.06333, 89.02387, 101.08406, 92.05002),
        molmass = c(169.012, 136.148, 91.109, 89.070, 101.147, 92.119),
        kegg = c("C07279", "C06224", "C06057", "C03834", "C10974", "C03084"),
        name = c("2-Aminoethylarsonate", "3,4-Dihydroxystyrene", "3-aminopropane-1,2-diol", "3-hydroxymonocarboxylic acid", "4-Methylaminobutanal", "4-Substituted aniline"),
        smiles = c("NCC[As](O)(O)=O", "Oc1ccc(C=C)cc1O", "NC[C@H](O)CO", "OC([*])CC(O)=O", "CNCCCC=O", "Nc1ccc([*])cc1"),
        description = c("", "", "", "", "", ""),
        stringsAsFactors = FALSE
    )
    write.table(df, "input.csv", sep = ";", row.names = FALSE, quote = FALSE)
}