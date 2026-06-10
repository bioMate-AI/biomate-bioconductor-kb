suppressPackageStartupMessages({
    library(openCyto)
    library(flowWorkspaceData)
    library(data.table)
})

# 1. fcsFiles: raw FCS files
# The workflow expects FCS files. We create a directory named 'fcsFiles' 
# and populate it with example FCS files from the flowWorkspaceData package.
fcs_dir <- system.file("extdata", package = "flowWorkspaceData")
fcs_paths <- list.files(fcs_dir, pattern = "CytoTrol.*\\.fcs$", full.names = TRUE)

if (length(fcs_paths) == 0) {
    fcs_paths <- list.files(fcs_dir, pattern = "\\.fcs$", full.names = TRUE)
}

dir.create("fcsFiles", showWarnings = FALSE)
file.copy(fcs_paths, file.path("fcsFiles", basename(fcs_paths)), overwrite = TRUE)

# Also copy to the working directory in case the workflow expects them at the root
file.copy(fcs_paths, basename(fcs_paths), overwrite = TRUE)

# 2. gtFile: CSV gating template defining the hierarchical gating scheme
gt_path <- system.file("extdata/gating_template/tcell.csv", package = "openCyto")

if (file.exists(gt_path)) {
    file.copy(gt_path, "gtFile", overwrite = TRUE)
    file.copy(gt_path, "gtFile.csv", overwrite = TRUE)
} else {
    # Fallback minimal template if the exact file is not found
    dtTemplate <- data.table(
        alias = c("nonDebris", "singlets", "lymph", "cd3"),
        pop = c("+", "+", "+", "+"),
        parent = c("root", "nonDebris", "singlets", "lymph"),
        dims = c("FSC-A", "FSC-A,FSC-H", "FSC-A,SSC-A", "CD3"),
        gating_method = c("gate_mindensity", "singletGate", "flowClust", "gate_mindensity"),
        gating_args = c(NA, NA, "K=2,target=c(1e5,5e4)", NA),
        collapseDataForGating = c(NA, NA, NA, TRUE),
        groupBy = c(NA, NA, NA, 4),
        preprocessing_method = c(NA, NA, "prior_flowClust", NA),
        preprocessing_args = c(NA, NA, NA, NA)
    )
    fwrite(dtTemplate, "gtFile")
    fwrite(dtTemplate, "gtFile.csv")
}