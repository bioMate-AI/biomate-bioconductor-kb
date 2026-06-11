library(seqsetvis)
library(GenomicRanges)

# Load the example dataset from the seqsetvis package
data("CTCF_in_10a_narrowPeak_grs", package = "seqsetvis")

# Initialize the named character vector for the input files
np_files <- character()

# Serialize each GRanges object into a BED file in the working directory
for (sample_name in names(CTCF_in_10a_narrowPeak_grs)) {
    gr <- CTCF_in_10a_narrowPeak_grs[[sample_name]]
    out_file <- paste0(sample_name, ".bed")
    
    # Construct a standard BED format data frame (0-based start, 1-based end)
    bed_df <- data.frame(
        chrom = as.character(seqnames(gr)),
        chromStart = start(gr) - 1,
        chromEnd = end(gr),
        name = paste0(sample_name, "_peak_", seq_along(gr)),
        score = if (!is.null(gr$score)) gr$score else 0,
        strand = as.character(strand(gr))
    )
    
    # Replace '*' strand with '.' for standard BED compatibility
    bed_df$strand[bed_df$strand == "*"] <- "."
    
    # Write to file without headers or row names
    write.table(bed_df, file = out_file, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
    
    # Append to the named vector
    np_files[sample_name] <- out_file
}

# Verify the files exist
stopifnot(all(file.exists(np_files)))