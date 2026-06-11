library(RMassBank)
library(RMassBankData)

# Initialize default settings required by RMassBank
RmbDefaultSettings()

# 1. Create processed_workspace.RData
# Load the pre-processed workspace from RMassBankData as shown in the vignette
w <- loadMsmsWorkspace(system.file("results/pH_narcotics_RF.RData", package="RMassBankData"))
mb <- newMbWorkspace(w)
save(mb, file="processed_workspace.RData")

# 2. Create infolists_incomplete directory and Narcotics_infolist.csv
dir.create("infolists_incomplete", showWarnings = FALSE)

# Find an existing infolist in RMassBankData to use as a template
infolist_files <- list.files(
    system.file(package="RMassBankData"), 
    pattern="infolist.*\\.csv$", 
    ignore.case=TRUE, 
    recursive=TRUE, 
    full.names=TRUE
)

if (length(infolist_files) > 0) {
    file.copy(infolist_files[1], "infolists_incomplete/Narcotics_infolist.csv", overwrite=TRUE)
    file.copy(infolist_files[1], "Narcotics_infolist.csv", overwrite=TRUE)
} else {
    # Fallback: create a minimal valid infolist if not found
    dummy_infolist <- data.frame(
        id = 1,
        name = "Dummy",
        formula = "C",
        exactmass = 12.0,
        SMILES = "C",
        InChI = "InChI=1S/C",
        InChIKey = "dummy"
    )
    write.csv(dummy_infolist, "infolists_incomplete/Narcotics_infolist.csv", row.names=FALSE)
    write.csv(dummy_infolist, "Narcotics_infolist.csv", row.names=FALSE)
}