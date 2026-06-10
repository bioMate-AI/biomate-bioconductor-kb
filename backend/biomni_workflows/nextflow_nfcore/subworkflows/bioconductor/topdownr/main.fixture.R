library("topdownr")

# Create target_mz_matrix.csv based on the vignette's targetMz object
targetMz <- cbind(mz = c(560.6, 700.5, 933.7), z = rep(1, 3))
write.csv(as.data.frame(targetMz), "target_mz_matrix.csv", row.names = FALSE)

# Locate and copy the template method file shipped with the package
meth_file <- list.files(system.file("extdata", package = "topdownr"), 
                        pattern = "TMS2IndependentTemplateForTD.meth", 
                        recursive = TRUE, full.names = TRUE)

if (length(meth_file) > 0 && file.exists(meth_file[1])) {
    file.copy(meth_file[1], "TMS2IndependentTemplateForTD.meth", overwrite = TRUE)
} else {
    # Fallback to ensure the file exists if not found in extdata
    writeLines("Dummy method file content", "TMS2IndependentTemplateForTD.meth")
}