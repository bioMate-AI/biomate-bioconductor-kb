library(AlphaBeta)

# Locate the example pedigree files shipped with the package
sampleFile <- system.file("extdata/vg", "nodelist.fn", package = "AlphaBeta")
edgesFile <- system.file("extdata/vg", "edgelist.fn", package = "AlphaBeta")

# Read the nodelist to identify and extract the referenced methylome files
nodes <- read.delim(sampleFile, stringsAsFactors = FALSE)

# Identify the column containing file paths (usually 'File' or 'path')
file_col <- grep("file|path", colnames(nodes), ignore.case = TRUE, value = TRUE)

if (length(file_col) > 0) {
    file_col <- file_col[1]
    for (i in seq_len(nrow(nodes))) {
        fname <- basename(nodes[[file_col]][i])
        
        # Search for the methylome file in the package's extdata directory
        pkg_file <- list.files(system.file("extdata", package = "AlphaBeta"), 
                               pattern = paste0("^", fname, "$"), 
                               recursive = TRUE, 
                               full.names = TRUE)
        
        if (length(pkg_file) > 0) {
            # Copy the existing file to the working directory
            file.copy(pkg_file[1], fname, overwrite = TRUE)
        } else {
            # Create a minimal dummy methimpute file if the specific file is not shipped
            dummy_meth <- data.frame(
                seqnames = rep("chr1", 10),
                start = seq(100, 1000, by = 100),
                end = seq(100, 1000, by = 100),
                context = rep("CG", 10),
                counts.methylated = sample(0:10, 10, replace = TRUE),
                counts.unmethylated = sample(0:10, 10, replace = TRUE),
                posteriorMax = runif(10, 0.9, 1.0),
                status = sample(c("methylated", "unmethylated"), 10, replace = TRUE)
            )
            write.table(dummy_meth, fname, sep = "\t", row.names = FALSE, quote = FALSE)
        }
        
        # Update the nodelist to reference the local file in the working directory
        nodes[[file_col]][i] <- fname
    }
}

# Write the updated nodelist.fn to the working directory
write.table(nodes, "nodelist.fn", sep = "\t", row.names = FALSE, quote = FALSE)

# Copy the edgelist.fn to the working directory
file.copy(edgesFile, "edgelist.fn", overwrite = TRUE)