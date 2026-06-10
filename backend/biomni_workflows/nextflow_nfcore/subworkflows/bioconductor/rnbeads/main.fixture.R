suppressPackageStartupMessages({
    library(RnBeads)
})

# Construct a synthetic sample annotation table
sa_data <- data.frame(
    Sample_ID = paste0("sample", 1:4),
    Sample_Group = rep(c("Group1", "Group2"), each = 2),
    Sentrix_ID = rep("1234567890", 4),
    Sentrix_Position = sprintf("R%02dC01", 1:4),
    stringsAsFactors = FALSE
)

# Write the sample annotation CSV as expected by the workflow
write.csv(sa_data, "sample_annotation.csv", row.names = FALSE)

# Create the idat directory and populate it with synthetic raw IDAT files
dir.create("idat", showWarnings = FALSE)
for (i in seq_len(nrow(sa_data))) {
    base_name <- paste0(sa_data$Sentrix_ID[i], "_", sa_data$Sentrix_Position[i])
    
    # Write dummy binary data to simulate IDAT files
    writeBin(as.raw(1:100), file.path("idat", paste0(base_name, "_Grn.idat")))
    writeBin(as.raw(1:100), file.path("idat", paste0(base_name, "_Red.idat")))
}