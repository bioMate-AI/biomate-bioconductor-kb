# [biomate] structured fixture (rule: extdata_copy) — deterministic, no LLM
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ballgown")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ballgown)
file.copy(system.file("extdata", "sample01/e_data.ctab", package="ballgown"), "e_data.ctab", overwrite=TRUE)
file.copy(system.file("extdata", "sample01/i_data.ctab", package="ballgown"), "i_data.ctab", overwrite=TRUE)
file.copy(system.file("extdata", "sample01/t_data.ctab", package="ballgown"), "t_data.ctab", overwrite=TRUE)
file.copy(system.file("extdata", "sample01/e2t.ctab", package="ballgown"), "e2t.ctab", overwrite=TRUE)
file.copy(system.file("extdata", "sample01/i2t.ctab", package="ballgown"), "i2t.ctab", overwrite=TRUE)
