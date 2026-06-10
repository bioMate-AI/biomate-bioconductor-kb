library(MSnID)
library(Biostrings)

# Copy the mzIdentML file from the package's extdata
mzid_src <- system.file("extdata", "phospho.mzid.gz", package="MSnID")
if (file.exists(mzid_src)) {
    file.copy(mzid_src, "phospho.mzid.gz", overwrite = TRUE)
} else {
    # Fallback: construct a minimal synthetic mzIdentML file
    mzid_content <- '<?xml version="1.0" encoding="UTF-8"?>\n<MzIdentML id="123" version="1.1.0" xmlns="http://psidev.info/psi/pi/mzIdentML/1.1"></MzIdentML>'
    con <- gzfile("phospho.mzid.gz", "w")
    writeLines(mzid_content, con)
    close(con)
}

# Copy the FASTA file from the package's extdata
fasta_src <- system.file("extdata", "for_phospho.fasta.gz", package="MSnID")
if (file.exists(fasta_src)) {
    file.copy(fasta_src, "for_phospho.fasta.gz", overwrite = TRUE)
} else {
    # Fallback: construct a minimal synthetic FASTA file
    con <- gzfile("for_phospho.fasta.gz", "w")
    writeLines(c(">sp|P12345|PROT", "MABCDEFGHIKLMNPQRSTVWXYZ"), con)
    close(con)
}