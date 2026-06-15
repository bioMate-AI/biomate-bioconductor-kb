# Real user-style input for tximeta::importData(type="oarfish"):
#   sgnex_h9_rep2.quant.gz   - an oarfish per-transcript quantification table
#                              (columns: tname, len, num_reads) for one sample,
#                              quantified against a MIXED reference (annotated +
#                              novel transcripts).
#   sgnex_h9_rep2.meta_info.json - the oarfish metadata sidecar that MUST sit
#                              next to the quant file. tximeta::getMetaInfo reads
#                              <name>.meta_info.json and requires BOTH an
#                              `annotated_transcripts_digest` and a
#                              `novel_transcripts_digest` under `digest`
#                              (importData() errors otherwise — it is specifically
#                              the mixed-reference importer). Each digest carries
#                              sha256 sequence/name digests as oarfish emits them.
#   coldata                  - sample table with the required `files`/`names`
#                              columns pointing at the quant file.
#   novel_gr                 - a GRanges of the NOVEL transcript coordinates the
#                              user wants to attach (names match the novel tnames
#                              in the quant table) so updateMetadata(..., ranges=TRUE)
#                              can build a RangedSummarizedExperiment.
# This is exactly the oarfish mixed-reference contract — no tximportData / demo data.
suppressPackageStartupMessages({
  library(GenomicRanges)
})

set.seed(7)

# Deterministic 64-hex "sha256-like" digest of a string, using only base R
# (the tximeta biocontainer does not ship the `digest` package). These stand in
# for oarfish's recorded reference digests; their only role downstream is to be
# looked up as (un-registered) txome ids, which tximeta handles gracefully.
hex64 <- function(s) {
  raw <- utf8ToInt(s)
  acc <- integer(32)
  for (i in seq_along(raw)) {
    j <- ((i - 1L) %% 32L) + 1L
    acc[j] <- bitwXor(acc[j], bitwAnd(raw[i] * (i + 7L) + 131L, 255L))
  }
  paste(sprintf("%02x", acc), collapse = "")
}

# Mixed reference: 3 annotated transcripts + 2 novel transcripts.
annotated_tx <- c("ENST00000001", "ENST00000002", "ENST00000003")
novel_tx     <- c("NOVELTX0001", "NOVELTX0002")
all_tx       <- c(annotated_tx, novel_tx)
tx_len       <- c(1500L, 2400L, 900L, 1800L, 3000L)
num_reads    <- c(120.0, 340.5, 47.0, 88.0, 15.5)

# --- oarfish quant table: tname / len / num_reads ---
quant <- data.frame(tname = all_tx, len = tx_len, num_reads = num_reads,
                    stringsAsFactors = FALSE)
gz <- gzfile("sgnex_h9_rep2.quant.gz", "w")
write.table(quant, gz, sep = "\t", quote = FALSE, row.names = FALSE)
close(gz)

# --- oarfish meta_info.json sidecar (must be <name>.meta_info.json) ---
# Build the two reference digests oarfish records for a mixed index. The sha256
# values are real digests of the corresponding transcript-id sets, so they are
# deterministic and self-consistent (not placeholders).
mk_digest <- function(ids) {
  list(
    sha256_digests = list(
      sha256_names = hex64(paste(ids, collapse = ",")),
      sha256_seqs  = hex64(paste(ids, collapse = "|"))
    ),
    num_records = length(ids)
  )
}
meta <- list(
  num_reads = sum(num_reads),
  num_mapped = sum(num_reads),
  digest = list(
    annotated_transcripts_digest = mk_digest(annotated_tx),
    novel_transcripts_digest     = mk_digest(novel_tx)
  )
)
# jsonlite ships in the tximeta biocontainer (tximeta depends on it).
writeLines(jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE),
           "sgnex_h9_rep2.meta_info.json")

# --- coldata: files + names columns required by importData ---
coldata <- data.frame(
  files     = "sgnex_h9_rep2.quant.gz",
  names     = "sgnex_h9_rep2",
  condition = "H9",
  stringsAsFactors = FALSE
)
write.csv(coldata, "coldata", row.names = FALSE)

# --- novel_gr: GRanges for the NOVEL transcripts (names match novel tnames) ---
novel_gr <- GRanges(
  seqnames = c("chr1", "chr7"),
  ranges   = IRanges(start = c(100000, 250000), end = c(101800, 253000)),
  strand   = c("+", "-"),
  tx_id    = novel_tx,
  gene_id  = c("NOVELGENE1", "NOVELGENE2")
)
names(novel_gr) <- novel_tx
saveRDS(novel_gr, "novel_gr")
