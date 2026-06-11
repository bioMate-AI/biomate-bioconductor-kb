library(scifer)

# 1. .fcs files (flow cytometry index sorting data)
fcs_dir <- system.file("extdata", "fcs_index_sorting", package = "scifer")
if (nzchar(fcs_dir) && dir.exists(fcs_dir)) {
    # Copy the folder itself to preserve structure if needed
    file.copy(fcs_dir, ".", recursive = TRUE)
    # Copy individual .fcs files to the working directory
    fcs_files <- list.files(fcs_dir, pattern = "\\.fcs$", full.names = TRUE, recursive = TRUE)
    file.copy(fcs_files, ".")
}

# 2. .ab1 files (raw Sanger sequencing chromatogram files)
sanger_dir <- system.file("extdata", "sorted_sangerseq", package = "scifer")
if (nzchar(sanger_dir) && dir.exists(sanger_dir)) {
    # Copy the folder itself to preserve subfolder structure matching .fcs files
    file.copy(sanger_dir, ".", recursive = TRUE)
    # Copy individual .ab1 files to the working directory
    ab1_files <- list.files(sanger_dir, pattern = "\\.ab1$", full.names = TRUE, recursive = TRUE)
    file.copy(ab1_files, ".")
}

# 3. IgBlast database folder (containing V.fasta, D.fasta, J.fasta)
kimdb_dir <- system.file("extdata", "test_fasta", "KIMDB_rm", package = "scifer")
if (!nzchar(kimdb_dir) || !dir.exists(kimdb_dir)) {
    # Fallback to root extdata if test_fasta subfolder is not present
    kimdb_dir <- system.file("extdata", "KIMDB_rm", package = "scifer")
}

if (nzchar(kimdb_dir) && dir.exists(kimdb_dir)) {
    file.copy(kimdb_dir, ".", recursive = TRUE)
} else {
    # Construct synthetic IgBlast database folder if not found
    dir.create("KIMDB_rm", showWarnings = FALSE)
    writeLines(">V_gene\nATGC", "KIMDB_rm/V.fasta")
    writeLines(">D_gene\nATGC", "KIMDB_rm/D.fasta")
    writeLines(">J_gene\nATGC", "KIMDB_rm/J.fasta")
}

# 4. Additional fasta file used in the vignette for igblast()
test_fasta <- system.file("extdata", "test_fasta", "test_igblast.txt", package = "scifer")
if (nzchar(test_fasta) && file.exists(test_fasta)) {
    file.copy(test_fasta, ".")
} else {
    writeLines(">test1\nACCCGGGGGGCTGCAGACATAGGGAGGTGCTCTTGGGAGGGGGCCCCGGGGGGAAGCCAAAAGGGCCCTTTGGTGAAGGGGGGAAAAAAAGACCAGGACCCCCGGGGCCCAAGAAAAAAAGCGGACCTTCTGCCTCAACTTTTTCAAAATCTTTGCTGACGGGTGGCCTCTACTCAGGCCATGTGTTTGAGAAAGTCGAAGATGGTTTTTGTTTTCGGGGGGGAGACTGTAGCTGCGCAATTTCAAATCTGGACACAATGAGTTTTCCCACTAGGATTATACTTAAAACCCACCTATACCCCCTCCCCTGCAGCCTGTTGGACTACCTTTTAGTAAAAATTACTCAGGCTAAAACCGCAGATGCTAAGGAAAGGACTCACGAACACCCAGACTTTCGGACCCTGCCCCCCTAATACACCTCCTTCGGACCATAAAATTGAACACCTCTAAAGGGAAGCAGAAGA", "test_igblast.txt")
}