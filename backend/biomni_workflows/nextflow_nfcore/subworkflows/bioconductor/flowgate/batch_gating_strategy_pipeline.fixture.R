library(flowGate)
library(flowCore)
library(flowWorkspace)

path_to_fcs <- system.file("extdata", package = "flowGate")
fs <- read.flowSet(path = path_to_fcs, pattern = ".FCS$", full.names = TRUE)

gs_obj <- GatingSet(fs)

path_to_comp <- system.file("extdata", "compdata", "compmatrix", package = "flowCore")
comp_matrix <- read.table(path_to_comp, header = TRUE, skip = 2, check.names = FALSE)
comp <- compensation(comp_matrix)
gs_obj <- compensate(gs_obj, comp)

# Save the GatingSet to the directory expected by the workflow
save_gs(gs_obj, path = "gs")