# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Seqinfo", "qtl", "qpgraph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Seqinfo)
library(qtl)
library(qpgraph)

# Reproduce vignette code for 'map' (chunk 4)
map <- sim.map(len=rep(100, times=9),
               n.mar=rep(10, times=9),
               anchor.tel=FALSE,
               eq.spacing=TRUE,
               include.x=FALSE)

# Reproduce vignette code for 'sim.eqtl' (chunk 5)
set.seed(12345)
sim.eqtl <- reQTLcross(eQTLcrossParam(map=map, genes=50, cis=0.5, trans=rep(5, 5)),
                       a=2, rho=0.5)

# Reproduce vignette code for 'cross' (chunk 7)
set.seed(12345)
cross <- sim.cross(map, sim.eqtl, n.ind=100)

# Reproduce vignette code for initial 'annot' (chunk 8)
annot <- data.frame(chr=as.character(sim.eqtl$genes[, "chr"]),
                    start=sim.eqtl$genes[, "location"],
                    end=sim.eqtl$genes[, "location"],
                    strand=rep("+", nrow(sim.eqtl$genes)),
                    row.names=rownames(sim.eqtl$genes),
                    stringsAsFactors=FALSE)

# Reproduce vignette code for 'pMap', 'genome', and modified 'annot' (chunk 9)
pMap <- lapply(map, function(x) x * 5)
class(pMap) <- "map"
annot$start <- floor(annot$start * 5)
annot$end <- floor(annot$end * 5)
genome <- Seqinfo(seqnames=names(map), seqlengths=rep(100 * 5, nchr(pMap)),
                  NA, "simulatedGenome")

# Serialize objects to the required input files
save(cross, file = "cross.RData")
save(pMap, file = "physical_map.RData")
write.csv(annot, file = "gene_annotation.csv", row.names = TRUE)
save(genome, file = "genome_info.RData")