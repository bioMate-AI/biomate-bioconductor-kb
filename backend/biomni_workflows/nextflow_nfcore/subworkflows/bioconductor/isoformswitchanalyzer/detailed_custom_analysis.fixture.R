library(IsoformSwitchAnalyzeR)

extdata_dir <- system.file("extdata", package="IsoformSwitchAnalyzeR")

# 1. salmon_quant_dir
salmon_src <- list.files(extdata_dir, pattern="salmon", full.names=TRUE, include.dirs=TRUE)
if (length(salmon_src) == 0) {
    salmon_src <- list.files(extdata_dir, pattern="kallisto", full.names=TRUE, include.dirs=TRUE)
}
dir.create("salmon_quant_dir", showWarnings = FALSE)
if (length(salmon_src) > 0 && file.info(salmon_src[1])$isdir) {
    file.copy(list.files(salmon_src[1], full.names=TRUE), "salmon_quant_dir", recursive=TRUE)
} else {
    for (sample in c("sample1", "sample2")) {
        d <- file.path("salmon_quant_dir", sample)
        dir.create(d, recursive = TRUE, showWarnings = FALSE)
        write.table(data.frame(Name=c("tx1", "tx2"), Length=c(100, 200), EffectiveLength=c(100, 200), TPM=c(10, 20), NumReads=c(50, 100)),
                    file=file.path(d, "quant.sf"), sep="\t", row.names=FALSE, quote=FALSE)
    }
}

# 2. annotation.gtf
gtf_src <- list.files(extdata_dir, pattern="\\.gtf", full.names=TRUE)
if (length(gtf_src) > 0) {
    file.copy(gtf_src[1], "annotation.gtf")
} else {
    writeLines(c(
        'chr1\tTEST\ttranscript\t1\t1000\t.\t+\t.\tgene_id "gene1"; transcript_id "tx1";',
        'chr1\tTEST\texon\t1\t1000\t.\t+\t.\tgene_id "gene1"; transcript_id "tx1";',
        'chr1\tTEST\ttranscript\t1\t1000\t.\t+\t.\tgene_id "gene1"; transcript_id "tx2";',
        'chr1\tTEST\texon\t1\t500\t.\t+\t.\tgene_id "gene1"; transcript_id "tx2";'
    ), "annotation.gtf")
}

# 3. transcript_sequences.fasta
fasta_src <- list.files(extdata_dir, pattern="\\.fasta|\\.fa", full.names=TRUE)
if (length(fasta_src) > 0) {
    file.copy(fasta_src[1], "transcript_sequences.fasta")
} else {
    writeLines(c(">tx1", "ATGCGTACGTAGCTAGCTAGCTAGCTAG", ">tx2", "ATGCGTACGTAGCTAGCTAGCTAGCTAG"), "transcript_sequences.fasta")
}

# 4. cpat_results.txt
cpat_src <- list.files(extdata_dir, pattern="cpat.*\\.txt", full.names=TRUE, ignore.case=TRUE)
if (length(cpat_src) > 0) {
    file.copy(cpat_src[1], "cpat_results.txt")
} else {
    writeLines(c("mRNA\tORF\tcoding_prob", "tx1\t100\t0.9", "tx2\t50\t0.1"), "cpat_results.txt")
}

# 5. cpc2_result.txt
cpc2_src <- list.files(extdata_dir, pattern="cpc2.*\\.txt", full.names=TRUE, ignore.case=TRUE)
if (length(cpc2_src) > 0) {
    file.copy(cpc2_src[1], "cpc2_result.txt")
} else {
    writeLines(c("#ID\ttranscript_length\tpeptide_length\tFickett_score\tpI\tORF_integrity\tcoding_probability\tlabel",
                 "tx1\t1000\t100\t1.0\t7.0\tcomplete\t0.9\tcoding",
                 "tx2\t500\t50\t0.5\t7.0\tcomplete\t0.1\tnoncoding"), "cpc2_result.txt")
}

# 6. pfam_results.txt
pfam_src <- list.files(extdata_dir, pattern="pfam.*\\.txt", full.names=TRUE, ignore.case=TRUE)
if (length(pfam_src) > 0) {
    file.copy(pfam_src[1], "pfam_results.txt")
} else {
    writeLines(c("seq_id\talignment_start\talignment_end\tenvelope_start\tenvelope_end\thmm_acc\thmm_name\ttype\thmm_start\thmm_end\thmm_length\tbit_score\tE-value\tsignificance\tclan",
                 "tx1\t1\t100\t1\t100\tPF00001\tTestDomain\tDomain\t1\t100\t100\t50.0\t1e-10\t1\tCL0001"), "pfam_results.txt")
}

# 7. signalP_results.txt
signalp_src <- list.files(extdata_dir, pattern="signalp.*\\.txt", full.names=TRUE, ignore.case=TRUE)
if (length(signalp_src) > 0) {
    file.copy(signalp_src[1], "signalP_results.txt")
} else {
    writeLines(c("# SignalP-5.0", "ID\tPrediction\tSP(Sec/SPI)\tOTHER\tCS Position", "tx1\tSP(Sec/SPI)\t0.99\t0.01\tCS pos: 20-21"), "signalP_results.txt")
}

# 8. iupred2a_result.txt.gz
iupred_src <- list.files(extdata_dir, pattern="iupred.*\\.txt\\.gz", full.names=TRUE, ignore.case=TRUE)
if (length(iupred_src) > 0) {
    file.copy(iupred_src[1], "iupred2a_result.txt.gz")
} else {
    gz <- gzfile("iupred2a_result.txt.gz", "w")
    writeLines(c(">tx1", "1\tM\t0.1", "2\tA\t0.2"), gz)
    close(gz)
}

# 9. netsurfp3_result.csv.gz
netsurf_src <- list.files(extdata_dir, pattern="netsurf.*\\.csv\\.gz", full.names=TRUE, ignore.case=TRUE)
if (length(netsurf_src) > 0) {
    file.copy(netsurf_src[1], "netsurfp3_result.csv.gz")
} else {
    gz <- gzfile("netsurfp3_result.csv.gz", "w")
    writeLines(c("id,seq,n,rsa,asa,q3,p[q3_H],p[q3_E],p[q3_C],q8,p[q8_G],p[q8_H],p[q8_I],p[q8_B],p[q8_E],p[q8_S],p[q8_T],p[q8_C],phi,psi,disorder",
                 "tx1,M,1,0.5,50,C,0.1,0.1,0.8,C,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.65,-60,45,0.1"), gz)
    close(gz)
}

# 10. deeploc2.csv
deeploc_src <- list.files(extdata_dir, pattern="deeploc.*\\.csv", full.names=TRUE, ignore.case=TRUE)
if (length(deeploc_src) > 0) {
    file.copy(deeploc_src[1], "deeploc2.csv")
} else {
    writeLines(c("Protein_ID,Localizations,Signals", "tx1,Nucleus,None"), "deeploc2.csv")
}

# 11. DeepTMHMM.gff3
deeptmhmm_src <- list.files(extdata_dir, pattern="deeptmhmm.*\\.gff3", full.names=TRUE, ignore.case=TRUE)
if (length(deeptmhmm_src) > 0) {
    file.copy(deeptmhmm_src[1], "DeepTMHMM.gff3")
} else {
    writeLines(c("##gff-version 3", "tx1\tDeepTMHMM\tTMhelix\t10\t30\t.\t.\t.\t."), "DeepTMHMM.gff3")
}