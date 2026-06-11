library(CytoPipeline)

rawDataDir <- system.file("extdata", package = "CytoPipeline")

# Copy FCS files to the working directory
fcs_files <- list.files(rawDataDir, pattern = "Donor", full.names = TRUE)
for (f in fcs_files) {
    file.copy(f, basename(f), overwrite = TRUE)
}

# Copy JSON file to the working directory
json_file <- file.path(rawDataDir, "OMIP021_flowAI_pipeline.json")
if (file.exists(json_file)) {
    file.copy(json_file, "OMIP021_flowAI_pipeline.json", overwrite = TRUE)
} else {
    # Fallback if not found
    json_content <- '{
      "experimentName": "OMIP021_flowAI",
      "scaleTransformProcessingQueue": [],
      "flowFramesPreProcessingQueue": []
    }'
    writeLines(json_content, "OMIP021_flowAI_pipeline.json")
}

# Create 'sampleFiles' to satisfy the literal file requirement
writeLines(basename(fcs_files), "sampleFiles")