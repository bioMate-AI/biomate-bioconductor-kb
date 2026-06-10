library(openCyto)
library(CytoML)
library(flowWorkspaceData)
library(flowWorkspace)

flowDataPath <- system.file("extdata", package = "flowWorkspaceData")
wsfile <- list.files(flowDataPath, pattern="manual.xml", full = TRUE)[1]
ws <- open_flowjo_xml(wsfile)
gs_obj <- flowjo_to_gatingset(ws, name = "T-cell", subset = 1)

if (dir.exists("gs")) {
    unlink("gs", recursive = TRUE)
}
save_gs(gs_obj, "gs")