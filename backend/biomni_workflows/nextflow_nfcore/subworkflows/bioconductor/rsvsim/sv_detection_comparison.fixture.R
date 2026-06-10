# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RSVSim", "Biostrings")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RSVSim)
library(Biostrings)

# Reproduce the vignette's toy genome
genome = DNAStringSet(
  c("AAAAAAAAAAAAAAAAAAAATTTTTTTTTTTTTTTTTTTT", 
    "GGGGGGGGGGGGGGGGGGGGCCCCCCCCCCCCCCCCCCCC")
)
names(genome) = c("chr1","chr2")

# Simulate structural variations (deletions) as shown in the vignette
sim = simulateSV(output=NA, genome=genome, dels=5, sizeDels=5,
                 bpSeqSize=10, seed=2345, verbose=FALSE)
simSVs = metadata(sim)$deletions

# Reproduce the vignette's query SVs data.frame
querySVs = data.frame(
  chr=c("chr1","chr1","chr1","chr2","chr2"),
  start=c(12,17,32,2,16), 
  end=c(15,24,36,6,20), 
  bpSeq=c("AAAAAAAAAA", "AAAAAAATTT", "TTTTTTTTTT", 
          "GGGGGGGGGG", "GGGGGGCCCC")
)

# Write the query SVs to a BED format file (tab-separated, no header, chr/start/end)
write.table(querySVs[, c("chr", "start", "end")], 
            file="query_svs.bed", 
            sep="\t", 
            quote=FALSE, 
            row.names=FALSE, 
            col.names=FALSE)

# Write the simulated SVs metadata to a CSV file
write.csv(as.data.frame(simSVs), 
          file="simulated_svs.csv", 
          row.names=FALSE)