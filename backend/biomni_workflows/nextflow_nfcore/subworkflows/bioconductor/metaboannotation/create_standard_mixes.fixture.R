# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MetaboAnnotation")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MetaboAnnotation)

candidates <- list.files(system.file("extdata", package="MetaboAnnotation"), 
                         pattern="Standard_list_example.txt", 
                         recursive=TRUE, 
                         full.names=TRUE)

if (length(candidates) > 0 && file.exists(candidates[1])) {
    file.copy(candidates[1], "Standard_list_example.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data matching the description
    df <- data.frame(
        name = c("NAE 20:4;O", "NAT 20:4;O", "NAE 20:3;O2"),
        formula = c("C22H37NO3", "C22H37NO5S", "C22H39NO4"),
        exactmass = c(363.2773, 427.2392, 381.2879),
        stringsAsFactors = FALSE
    )
    write.table(df, file = "Standard_list_example.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}