library(seqsetvis)
library(GenomicRanges)

bigwig_files = c(
    system.file("extdata", "MCF10A_CTCF_FE_random100.bw", package = "seqsetvis"),
    system.file("extdata", "MCF10AT1_CTCF_FE_random100.bw", package = "seqsetvis"),
    system.file("extdata", "MCF10CA1_CTCF_FE_random100.bw", package = "seqsetvis")
)
names(bigwig_files) = sub("_FE_random100.bw", "", basename(bigwig_files))

data(CTCF_in_10a_overlaps_gr)
olaps = CTCF_in_10a_overlaps_gr

saveRDS(bigwig_files, "bw_files")
saveRDS(olaps, "olaps")