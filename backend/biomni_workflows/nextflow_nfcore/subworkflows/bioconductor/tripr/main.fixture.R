library(tripr)

# Target files expected by the workflow
targets <- c(
  "1_Summary.txt",
  "2_IMGT-gapped-nt-sequences.txt",
  "4_IMGT-gapped-AA-sequences.txt",
  "6_Junction.txt"
)

# Search for existing files in the package's extdata
extdata_files <- list.files(system.file("extdata", package="tripr"), recursive=TRUE, full.names=TRUE)

for (tgt in targets) {
  matched <- grep(paste0(tgt, "$"), extdata_files, value=TRUE)
  if (length(matched) > 0) {
    file.copy(matched[1], tgt, overwrite = TRUE)
  } else {
    # Create synthetic files matching IMGT/HighV-Quest output format if not found
    if (tgt == "1_Summary.txt") {
      df <- data.frame(
        `Sequence number` = c(1, 2),
        `Sequence ID` = c("seq1", "seq2"),
        `Functionality` = c("productive", "productive"),
        `V-GENE and allele` = c("IGHV1-2*02", "IGHV3-21*01"),
        `J-GENE and allele` = c("IGHJ4*02", "IGHJ6*02"),
        `D-GENE and allele` = c("IGHD3-10*01", "IGHD3-22*01"),
        `V-REGION identity %` = c(98.5, 100.0),
        `CDR3-IMGT length` = c(15, 12),
        check.names = FALSE
      )
      write.table(df, tgt, sep="\t", row.names=FALSE, quote=FALSE)
    } else if (tgt == "2_IMGT-gapped-nt-sequences.txt") {
      df <- data.frame(
        `Sequence number` = c(1, 2),
        `Sequence ID` = c("seq1", "seq2"),
        `V-D-J-REGION` = c("ATGC", "ATGC"),
        check.names = FALSE
      )
      write.table(df, tgt, sep="\t", row.names=FALSE, quote=FALSE)
    } else if (tgt == "4_IMGT-gapped-AA-sequences.txt") {
      df <- data.frame(
        `Sequence number` = c(1, 2),
        `Sequence ID` = c("seq1", "seq2"),
        `V-D-J-REGION` = c("MAC", "MAC"),
        check.names = FALSE
      )
      write.table(df, tgt, sep="\t", row.names=FALSE, quote=FALSE)
    } else if (tgt == "6_Junction.txt") {
      df <- data.frame(
        `Sequence number` = c(1, 2),
        `Sequence ID` = c("seq1", "seq2"),
        `JUNCTION` = c("TGTGCGAGAG", "TGTGCGAGAG"),
        `JUNCTION_AA` = c("CAR", "CAR"),
        check.names = FALSE
      )
      write.table(df, tgt, sep="\t", row.names=FALSE, quote=FALSE)
    }
  }
}