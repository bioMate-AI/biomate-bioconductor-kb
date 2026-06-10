library(IsoformSwitchAnalyzeR)

# 1. salmon_quant_dir
quant_dir <- system.file("extdata/quantification", package="IsoformSwitchAnalyzeR")
dir.create("salmon_quant_dir", showWarnings = FALSE)
if (dir.exists(quant_dir) && length(list.files(quant_dir)) > 0) {
    file.copy(list.files(quant_dir, full.names = TRUE), "salmon_quant_dir", recursive = TRUE)
} else {
    # Fallback synthetic data
    dir.create("salmon_quant_dir/sample1", recursive = TRUE, showWarnings = FALSE)
    write.table(data.frame(Name="tx1", Length=100, EffectiveLength=100, TPM=10, NumReads=100), 
                "salmon_quant_dir/sample1/quant.sf", sep="\t", row.names=FALSE, quote=FALSE)
}

# 2. annotation.gtf
gtf_file <- list.files(system.file("extdata", package="IsoformSwitchAnalyzeR"), pattern="\\.gtf", full.names=TRUE)[1]
if (!is.na(gtf_file) && file.exists(gtf_file)) {
    if (grepl("\\.gz$", gtf_file)) {
        con <- gzfile(gtf_file, "rt")
        lines <- readLines(con)
        close(con)
        writeLines(lines, "annotation.gtf")
    } else {
        file.copy(gtf_file, "annotation.gtf", overwrite=TRUE)
    }
} else {
    writeLines(c(
        'chr1\tTEST\ttranscript\t1\t1000\t.\t+\t.\tgene_id "gene1"; transcript_id "tx1";',
        'chr1\tTEST\texon\t1\t1000\t.\t+\t.\tgene_id "gene1"; transcript_id "tx1";'
    ), "annotation.gtf")
}

# 3. transcript_sequences.fasta
fasta_file <- list.files(system.file("extdata", package="IsoformSwitchAnalyzeR"), pattern="\\.fasta$|\\.fa$", full.names=TRUE)[1]
if (!is.na(fasta_file) && file.exists(fasta_file)) {
    file.copy(fasta_file, "transcript_sequences.fasta", overwrite=TRUE)
} else {
    writeLines(c(">tx1", "ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG"), "transcript_sequences.fasta")
}

# 4. cpc2_result.txt
cpc2_file <- list.files(system.file("extdata", package="IsoformSwitchAnalyzeR"), pattern="cpc2", full.names=TRUE, ignore.case=TRUE)[1]
if (!is.na(cpc2_file) && file.exists(cpc2_file)) {
    file.copy(cpc2_file, "cpc2_result.txt", overwrite=TRUE)
} else {
    writeLines(c("#ID\ttranscript_length\tpeptide_length\tFickett_score\tpI\tORF_integrity\tcoding_probability\tlabel",
                 "tx1\t1000\t100\t1.0\t7.0\tcomplete\t0.9\tcoding"), "cpc2_result.txt")
}

# 5. pfam_results.txt
pfam_file <- list.files(system.file("extdata", package="IsoformSwitchAnalyzeR"), pattern="pfam", full.names=TRUE, ignore.case=TRUE)[1]
if (!is.na(pfam_file) && file.exists(pfam_file)) {
    file.copy(pfam_file, "pfam_results.txt", overwrite=TRUE)
} else {
    writeLines(c("seq_id\talignment_start\talignment_end\tenvelope_start\tenvelope_end\thmm_acc\thmm_name\ttype\thmm_start\thmm_end\thmm_length\tbit_score\tE-value\tsignificance\tclan\tpredicted_active_site_residues",
                 "tx1\t1\t100\t1\t100\tPF00001\tTestDomain\tDomain\t1\t100\t100\t100.0\t1e-10\t1\tCL0001\t"), "pfam_results.txt")
}

# 6. iupred2a_result.txt.gz
iupred_file <- list.files(system.file("extdata", package="IsoformSwitchAnalyzeR"), pattern="iupred", full.names=TRUE, ignore.case=TRUE)[1]
if (!is.na(iupred_file) && file.exists(iupred_file)) {
    if (!grepl("\\.gz$", iupred_file)) {
        con <- file(iupred_file, "rt")
        lines <- readLines(con)
        close(con)
        gz <- gzfile("iupred2a_result.txt.gz", "wt")
        writeLines(lines, gz)
        close(gz)
    } else {
        file.copy(iupred_file, "iupred2a_result.txt.gz", overwrite=TRUE)
    }
} else {
    gz <- gzfile("iupred2a_result.txt.gz", "wt")
    writeLines(c(">tx1", "1 M 0.1", "2 A 0.2"), gz)
    close(gz)
}

# 7. signalP_results.txt
signalp_file <- list.files(system.file("extdata", package="IsoformSwitchAnalyzeR"), pattern="signalp", full.names=TRUE, ignore.case=TRUE)[1]
if (!is.na(signalp_file) && file.exists(signalp_file)) {
    file.copy(signalp_file, "signalP_results.txt", overwrite=TRUE)
} else {
    writeLines(c("# SignalP-5.0", "ID\tPrediction\tSP(Sec/SPI)\tOTHER\tCS Position", "tx1\tSP(Sec/SPI)\t0.9\t0.1\tCS pos: 20-21. V-A"), "signalP_results.txt")
}