# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ternarynet")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ternarynet)

i_exp <- as.integer(c(0,0,0, 0,0,0, 0,0,0, 0,0,0,
                        1,1,1, 1,1,1, 1,1,1, 1,1,1,
                        2,2,2, 2,2,2, 2,2,2, 2,2,2,
                        3,3,3, 3,3,3, 3,3,3, 3,3,3,
                        4,4,4, 4,4,4, 4,4,4, 4,4,4,
                        5,5,5, 5,5,5, 5,5,5, 5,5,5,
                        6,6,6, 6,6,6, 6,6,6, 6,6,6,
                        7,7,7, 7,7,7, 7,7,7, 7,7,7))

i_node <- as.integer(c(0,0,0, 1,1,1, 2,2,2, 3,3,3,
                        0,0,0, 1,1,1, 2,2,2, 3,3,3,
                        0,0,0, 1,1,1, 2,2,2, 3,3,3,
                        0,0,0, 1,1,1, 2,2,2, 3,3,3,
                        0,0,0, 1,1,1, 2,2,2, 3,3,3,
                        0,0,0, 1,1,1, 2,2,2, 3,3,3,
                        0,0,0, 1,1,1, 2,2,2, 3,3,3,
                        0,0,0, 1,1,1, 2,2,2, 3,3,3))

outcome <- as.integer(c(-1,0,1, -1,0,1, -1,0,1, -1,0,1,
                        -1,0,1, -1,0,1, -1,0,1, -1,0,1,
                        -1,0,1, -1,0,1, -1,0,1, -1,0,1,
                        -1,0,1, -1,0,1, -1,0,1, -1,0,1,
                        -1,0,1, -1,0,1, -1,0,1, -1,0,1,
                        -1,0,1, -1,0,1, -1,0,1, -1,0,1,
                        -1,0,1, -1,0,1, -1,0,1, -1,0,1,
                        -1,0,1, -1,0,1, -1,0,1, -1,0,1))

value <- c(0,1,2, 0,1,2, 0,1,2, 0,1,2,
            2,1,0, 0,1,2, 0,1,2, 0,1,2,
            2,1,0, 2,1,0, 0,1,2, 0,1,2,
            2,1,0, 2,1,0, 2,1,0, 0,1,2,
            2,1,0, 2,1,0, 2,1,0, 2,1,0,
            0,1,2, 2,1,0, 2,1,0, 2,1,0,
            0,1,2, 0,1,2, 2,1,0, 2,1,0,
            0,1,2, 0,1,2, 0,1,2, 2,1,0)

is_perturbation <- 
c(TRUE,TRUE,TRUE,  FALSE,FALSE,FALSE, FALSE,FALSE,FALSE, FALSE,FALSE,FALSE,
    FALSE,FALSE,FALSE,  TRUE,TRUE,TRUE, FALSE,FALSE,FALSE, FALSE,FALSE,FALSE,
    FALSE,FALSE,FALSE,  FALSE,FALSE,FALSE, TRUE,TRUE,TRUE, FALSE,FALSE,FALSE,
    FALSE,FALSE,FALSE,  FALSE,FALSE,FALSE, FALSE,FALSE,FALSE, TRUE,TRUE,TRUE,
    TRUE,TRUE,TRUE,  FALSE,FALSE,FALSE, FALSE,FALSE,FALSE, FALSE,FALSE,FALSE,
    FALSE,FALSE,FALSE,  TRUE,TRUE,TRUE, FALSE,FALSE,FALSE, FALSE,FALSE,FALSE,
    FALSE,FALSE,FALSE,  FALSE,FALSE,FALSE, TRUE,TRUE,TRUE, FALSE,FALSE,FALSE,
    FALSE,FALSE,FALSE,  FALSE,FALSE,FALSE, FALSE,FALSE,FALSE, TRUE,TRUE,TRUE)

indata <- data.frame(i_exp, i_node, outcome, value, is_perturbation)

write.csv(indata, file = "indata.csv", row.names = FALSE)