# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("proDA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(proDA)

src_file <- system.file("extdata", "proteinGroups.txt", package = "proDA")

if (file.exists(src_file)) {
    file.copy(src_file, "proteinGroups.txt", overwrite = TRUE)
} else {
    full_data <- data.frame(
        Protein.IDs = c("Q8IP47;Q9VJP8;Q9V435", "A0A023GPV6;A8JV04", "A0A023GQA5;P24156"),
        Majority.protein.IDs = c("Q8IP47;Q9VJP8", "A0A023GPV6", "A0A023GQA5"),
        Peptide.counts..all. = c("7;7;7", "2;2", "13;13"),
        Peptide.counts..razor.unique. = c("7;7;7", "2;2", "13;13"),
        Peptide.counts..unique. = c("7;7;7", "2;2", "13;13"),
        Protein.names = c("Protein A", "Protein B", "Protein C"),
        Only.identified.by.site = c("", "", ""),
        Reverse = c("", "", ""),
        Potential.contaminant = c("", "", ""),
        LFQ.intensity.CG1407.01 = c(0, 0, 0),
        LFQ.intensity.CG1407.02 = c(0, 0, 0),
        LFQ.intensity.CG1407.03 = c(0, 0, 0),
        LFQ.intensity.CG4676.01 = c(0, 0, 0),
        LFQ.intensity.CG4676.02 = c(0, 0, 1200000),
        LFQ.intensity.CG4676.03 = c(0, 0, 0),
        LFQ.intensity.S2R.01 = c(100000, 200000, 300000),
        LFQ.intensity.S2R.02 = c(110000, 210000, 310000),
        LFQ.intensity.S2R.03 = c(120000, 220000, 320000),
        stringsAsFactors = FALSE
    )
    write.table(full_data, "proteinGroups.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}