library(openCyto)
library(flowWorkspaceData)
library(CytoML)
library(flowWorkspace)

# 1. Reproduce the vignette's data-preparation code
flowDataPath <- system.file("extdata", package = "flowWorkspaceData")
wsfile <- list.files(flowDataPath, pattern="manual.xml", full = TRUE)[1]

# Parse the FlowJo workspace
ws <- open_flowjo_xml(wsfile)

# Convert the workspace to a GatingSet object
gs_obj <- flowjo_to_gatingset(ws, name = "T-cell", subset = 1)

# 2. Serialize the GatingSet object to the declared input directory "gs"
unlink("gs", recursive = TRUE)
save_gs(gs_obj, "gs")