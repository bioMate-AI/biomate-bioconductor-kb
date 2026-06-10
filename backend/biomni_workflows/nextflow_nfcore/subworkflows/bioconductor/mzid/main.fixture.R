# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("mzID")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(mzID)

exampleFiles <- list.files(system.file('extdata', package = 'mzID'), 
                           pattern = '\\.mzid$', full.names = TRUE)

if (length(exampleFiles) > 0) {
    file_to_read <- if (length(exampleFiles) >= 5) exampleFiles[5] else exampleFiles[1]
    mzResults <- mzID(file_to_read)
    flatResults <- flatten(mzResults)
    
    write.csv(flatResults, "intensity.csv", row.names = FALSE)
    
    coldata <- data.frame(
        sample = if (!is.null(flatResults$idFile)) unique(flatResults$idFile) else "sample1",
        condition = "control",
        stringsAsFactors = FALSE
    )
    write.csv(coldata, "coldata.csv", row.names = FALSE)
} else {
    intensity <- data.frame(id = 1:10, value = rnorm(10))
    write.csv(intensity, "intensity.csv", row.names = FALSE)
    
    coldata <- data.frame(sample = "sample1", condition = "control")
    write.csv(coldata, "coldata.csv", row.names = FALSE)
}