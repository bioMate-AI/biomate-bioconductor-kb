# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("survcomp", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(survcomp)
library(Biobase)

# Load the dataset as demonstrated in the vignette
data(breastCancerData)

# Extract survival times, survival events, and group indicators (gene expression)
# Using the mainz7g dataset from the vignette
surv_time <- pData(mainz7g)[ ,"t.dmfs"]
surv_event <- pData(mainz7g)[ ,"e.dmfs"]
group_indicator <- exprs(mainz7g)[1, ] # First gene expression as group indicator

# Combine into a single data frame
survival_data <- data.frame(
  time = surv_time,
  event = surv_event,
  group = group_indicator
)

# Write to a CSV file
write.csv(survival_data, "survival_data.csv", row.names = FALSE)

# Also save the ExpressionSet object as RDS in case the workflow expects the S4 object directly
saveRDS(mainz7g, "mainz7g.rds")