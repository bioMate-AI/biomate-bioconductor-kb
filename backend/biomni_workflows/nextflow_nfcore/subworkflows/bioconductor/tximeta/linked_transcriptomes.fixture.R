# Real user-style input for tximeta with a CUSTOM (linked) transcriptome:
#   quant.sf                  - a Salmon quantification table for the user's
#                               samples (per-transcript TPM / NumReads).
#   custom_transcriptome.fa.gz- the transcriptome FASTA the user quantified
#                               against (transcript IDs MATCH quant.sf).
#   custom_annotation.gtf.gz  - the matching GTF annotation (gene/transcript/exon
#                               records for every quantified transcript), so
#                               tximeta can attach genomic ranges.
# All three reference the SAME set of transcripts (a consistent custom
# transcriptome), which is exactly what a user feeds tximeta's linkedTxome
# workflow. No tximportData / package demo data.

set.seed(1)

# A handful of consistent transcripts on a single contig.
tx <- data.frame(
    tx_id   = c("FBtr0070129", "FBtr0070130", "FBtr0070131", "FBtr0070132", "FBtr0070133"),
    gene_id = c("FBgn0025637", "FBgn0025637", "FBgn0031208", "FBgn0031208", "FBgn0051973"),
    start   = c(1000, 1000, 5000, 5200, 9000),
    end     = c(1600, 1450, 5800, 6000, 9700),
    stringsAsFactors = FALSE
)
tx$len <- tx$end - tx$start + 1
seqs <- vapply(tx$len, function(L)
    paste(sample(c("A", "C", "G", "T"), L, replace = TRUE), collapse = ""), character(1))

# --- quant.sf ---
reads <- c(540, 320, 880, 120, 60)
efflen <- pmax(tx$len - 50, 1)
tpm <- reads / efflen
tpm <- round(1e6 * tpm / sum(tpm), 4)
quant <- data.frame(
    Name = tx$tx_id,
    Length = tx$len,
    EffectiveLength = efflen,
    TPM = tpm,
    NumReads = reads
)
write.table(quant, "quant.sf", sep = "\t", quote = FALSE, row.names = FALSE)

# --- transcriptome FASTA ---
gz <- gzfile("custom_transcriptome.fa.gz", "w")
for (i in seq_len(nrow(tx))) writeLines(c(paste0(">", tx$tx_id[i]), seqs[i]), gz)
close(gz)

# --- GTF (gene / transcript / exon per transcript) ---
gtf_lines <- character(0)
for (i in seq_len(nrow(tx))) {
    attr_g <- sprintf('gene_id "%s";', tx$gene_id[i])
    attr_t <- sprintf('gene_id "%s"; transcript_id "%s";', tx$gene_id[i], tx$tx_id[i])
    gtf_lines <- c(gtf_lines,
        sprintf("2L\tcustom\tgene\t%d\t%d\t.\t+\t.\t%s", tx$start[i], tx$end[i], attr_g),
        sprintf("2L\tcustom\ttranscript\t%d\t%d\t.\t+\t.\t%s", tx$start[i], tx$end[i], attr_t),
        sprintf("2L\tcustom\texon\t%d\t%d\t.\t+\t.\t%s", tx$start[i], tx$end[i], attr_t))
}
gz <- gzfile("custom_annotation.gtf.gz", "w")
writeLines(gtf_lines, gz)
close(gz)
