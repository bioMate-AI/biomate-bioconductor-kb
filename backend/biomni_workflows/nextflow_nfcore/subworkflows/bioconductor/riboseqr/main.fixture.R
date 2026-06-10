# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("riboSeqR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(riboSeqR)

datadir <- system.file("extdata", package = "riboSeqR")
chlamyFasta <- paste(datadir, "/rsem_chlamy236_deNovo.transcripts.fa", sep = "")
fastaCDS <- findCDS(fastaFile = chlamyFasta, 
                    startCodon = c("ATG"), 
                    stopCodon = c("TAG", "TAA", "TGA"))

ribofiles <- paste(datadir, 
                   "/chlamy236_plus_deNovo_plusOnly_Index", c(17,3,5,7), sep = "")
rnafiles <- paste(datadir, 
                  "/chlamy236_plus_deNovo_plusOnly_Index", c(10,12,14,16), sep = "")

riboDat <- readRibodata(ribofiles, replicates = c("WT", "WT", "M", "M"))
fCs <- frameCounting(riboDat, fastaCDS)
fS <- readingFrame(rC = fCs)
ffCs <- filterHits(fCs, lengths = c(27, 28), frames = list(1, 0), 
                   hitMean = 50, unqhitMean = 10, fS = fS)

cds_df <- as.data.frame(ffCs@CDS)
bed <- data.frame(
  chrom = cds_df$seqnames,
  chromStart = cds_df$start - 1,
  chromEnd = cds_df$end,
  name = paste0("region_", seq_len(nrow(cds_df))),
  score = 0,
  strand = cds_df$strand
)
write.table(bed, "regions.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)

coldata <- data.frame(
  sample = c("WT_1", "WT_2", "M_1", "M_2"),
  condition = c("WT", "WT", "M", "M"),
  ribofile = ribofiles,
  rnafile = rnafiles
)
write.csv(coldata, "coldata.csv", row.names=FALSE)