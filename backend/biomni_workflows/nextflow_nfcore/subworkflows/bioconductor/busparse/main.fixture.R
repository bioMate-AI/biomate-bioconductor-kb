suppressPackageStartupMessages({
  library(BUSpaRse)
})

# Create the required directory
dir.create("./out_hgmm100", showWarnings = FALSE, recursive = TRUE)

# 1. Create transcripts.txt (implicitly required by the workflow to map ECs to transcripts)
tx_content <- c(
  "ENST00000434970.2",
  "ENST00000415118.1",
  "ENST00000448914.1",
  "ENST00000632684.1",
  "ENST00000390583.1",
  "ENST00000431440.2"
)
writeLines(tx_content, "./out_hgmm100/transcripts.txt")

# 2. Create matrix.ec (Equivalence class file)
# Format: EC_ID \t comma_separated_transcript_indices
ec_content <- c(
  "0\t0,1,2",
  "1\t3",
  "2\t4,5"
)
writeLines(ec_content, "./out_hgmm100/matrix.ec")

# 3. Create output.sorted.txt (Sorted BUS output file)
# Format: Barcode \t UMI \t EC_ID \t Count
bus_content <- c(
  "AAAAAAAAAAGGGGGG\tCCCCCCCCCC\t0\t1",
  "AAAAAAAAAAGGGGGG\tCCCCCCCCCC\t1\t2",
  "BBBBBBBBBBGGGGGG\tDDDDDDDDDD\t2\t1"
)
writeLines(bus_content, "./out_hgmm100/output.sorted.txt")

# Verify files exist
stopifnot(
  file.exists("./out_hgmm100/output.sorted.txt"),
  file.exists("./out_hgmm100/matrix.ec"),
  file.exists("./out_hgmm100/transcripts.txt")
)