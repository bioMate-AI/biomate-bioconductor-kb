library(msa)
library(Biostrings)

src_file <- system.file("examples", "HemoglobinAA.fasta", package="msa")
if (src_file == "") {
    src_file <- system.file("examples/HemoglobinAA.fasta", package="msa")
}

if (file.exists(src_file)) {
    file.copy(src_file, "HemoglobinAA.fasta", overwrite = TRUE)
} else {
    # Fallback if the file is not found in the package installation
    seqs <- AAStringSet(c(
        HBA1_Homo_sapiens = "MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSHGSAQVKGHGKKVADALTNAVAHVDDMPNALSALSDLHAHKLRVDPVNFKLLSHCLLVTLAAHLPAEFTPAVHASLDKFLASVSTVLTSKYR",
        HBA1_Pan_troglodytes = "MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSHGSAQVKGHGKKVADALTNAVAHVDDMPNALSALSDLHAHKLRVDPVNFKLLSHCLLVTLAAHLPAEFTPAVHASLDKFLASVSTVLTSKYR",
        HBA1_Mus_musculus = "MVLSGEDKSNIKAAWGKIGGHGAEYGAEALERMFASFPTTKTYFPHFDVSHGSAQVKGHGKKVADALASAAGHLDDLPGALSALSDLHAHKLRVDPVNFKLLSHCLLVTLASHHPADFTPAVHASLDKFLASVSTVLTSKYR"
    ))
    writeXStringSet(seqs, "HemoglobinAA.fasta")
}