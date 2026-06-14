# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

# Copy the package's real shipped example data (extdata/Twins.csv) to the declared input.
# (The prior data("fit") referenced a dataset that does not exist in DirichletMultinomial.)
.src <- system.file("extdata", "Twins.csv", package = "DirichletMultinomial")
if (!nzchar(.src)) stop("DirichletMultinomial extdata Twins.csv not found")
file.copy(.src, "Twins.csv", overwrite = TRUE)
