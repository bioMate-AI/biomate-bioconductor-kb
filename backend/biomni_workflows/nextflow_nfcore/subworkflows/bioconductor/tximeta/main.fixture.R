suppressPackageStartupMessages({
    library(tximeta)
    library(tximportData)
})

# Locate the salmon quantification directory from the companion package
dir <- system.file("extdata/salmon_dm", package="tximportData")
srr_dir <- file.path(dir, "SRR1197474")

# Copy all salmon output files (including quant.sf and required JSON metadata) to the working directory
file.copy(list.files(srr_dir, full.names = TRUE), ".", recursive = TRUE)

# Create the coldata data.frame as shown in the vignette, pointing to the local quant.sf
coldata <- data.frame(
    files = "quant.sf",
    names = "SRR1197474",
    condition = "A",
    stringsAsFactors = FALSE
)

# Serialize coldata to a CSV file named 'coldata' as expected by the workflow
write.csv(coldata, "coldata", row.names = FALSE)