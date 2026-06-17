# Real user-style input: forward and reverse amplicon-sequencing haplotype FASTA
# files in the QSutils collapsed-haplotype format the user obtains after running
# their own NGS amplicon pipeline. Headers carry per-haplotype read counts as
# >Hpl_<id>|<nreads>|<freq>. The forward and reverse sets share several
# haplotypes (so IntersectStrandHpls yields a non-trivial intersection) plus a
# few strand-specific ones (sequencing-error candidates that get filtered).

set.seed(7)
bases <- c("A", "C", "G", "T")
make_seq <- function(n) paste(sample(bases, n, replace = TRUE), collapse = "")
mutate <- function(s, k) {
    cs <- strsplit(s, "")[[1]]
    pos <- sample(seq_along(cs), k)
    cs[pos] <- sample(bases, length(pos), replace = TRUE)
    paste(cs, collapse = "")
}

L <- 200
master <- make_seq(L)
# Shared (true) haplotypes: present on both strands
shared <- c(master,
            mutate(master, 2),
            mutate(master, 4),
            mutate(master, 6),
            mutate(master, 8))
shared_reads_fw <- c(5200, 1800, 900, 350, 120)
shared_reads_rv <- c(5000, 1700, 850, 300, 110)

# Strand-specific (likely error) haplotypes
fw_only <- c(mutate(master, 10), mutate(master, 12))
fw_only_reads <- c(40, 18)
rv_only <- c(mutate(master, 11), mutate(master, 13))
rv_only_reads <- c(35, 22)

write_ampl <- function(file, seqs, reads) {
    total <- sum(reads)
    lines <- character(0)
    for (i in seq_along(seqs)) {
        freq <- round(100 * reads[i] / total, 1)
        hdr <- sprintf(">Hpl_%d_%04d|%d|%.1f", i - 1L, i, reads[i], freq)
        lines <- c(lines, hdr, seqs[i])
    }
    writeLines(lines, file)
}

write_ampl("ToyData_FWReads.fna", c(shared, fw_only), c(shared_reads_fw, fw_only_reads))
write_ampl("ToyData_RVReads.fna", c(shared, rv_only), c(shared_reads_rv, rv_only_reads))
