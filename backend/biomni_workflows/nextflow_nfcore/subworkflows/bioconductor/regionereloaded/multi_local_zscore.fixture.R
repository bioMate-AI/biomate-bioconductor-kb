# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("regioneReloaded", "regioneR", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("regioneReloaded")
library("regioneR")
library("GenomicRanges")

set.seed(42)

AlienGenome <- toGRanges(data.frame(
  chr = c("AlChr1", "AlChr2", "AlChr3", "AlChr4"),
  start = c(rep(1, 4)),
  end = c(2e6, 1e6, 5e5, 1e5)
))

gnm <- AlienGenome
nreg <- 100

regA <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50,
  non.overlapping = TRUE,
  genome = gnm
)

regB <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50 ,
  non.overlapping = TRUE,
  genome = gnm
)

regC <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50,
  non.overlapping = TRUE,
  genome = gnm
)

vectorPerc <- seq(0.1, 0.9, 0.1)
RsetA <- similarRegionSet(
  GR = regA,
  name = "regA",
  genome = gnm,
  vectorPerc = vectorPerc
)

RsetB <- similarRegionSet(
  GR = regB,
  name = "regB",
  genome = gnm,
  vectorPerc = vectorPerc
)

RsetC <- similarRegionSet(
  GR = regC,
  name = "regC",
  genome = gnm,
  vectorPerc = vectorPerc
)

regAB <- c(sample(regA, nreg / 2), sample(regB, nreg / 2))
vectorPerc2 <- seq(0.2, 0.8, 0.2)
RsetAB <- similarRegionSet(
  GR = regAB,
  name = "regAB",
  genome = gnm,
  vectorPerc = vectorPerc2
)

reg_no_A <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50,
  non.overlapping = TRUE,
  genome = subtractRegions(gnm, regA)
)

reg_no_B <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50,
  non.overlapping = TRUE,
  genome = subtractRegions(gnm, regB)
)

reg_no_C <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50,
  non.overlapping = TRUE,
  genome = subtractRegions(gnm, regC)
)

reg_no_AB <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50,
  non.overlapping = TRUE,
  genome = subtractRegions(gnm, c(regA, regB))
)

reg_no_ABC <- createRandomRegions(
  nregions = nreg,
  length.mean = 100,
  length.sd = 50,
  non.overlapping = TRUE,
  genome = subtractRegions(gnm, c(regA, regB, regC))
)

dst <- sample(c(-300, 300), length(regA), replace = TRUE)
regD <- regioneR::toGRanges(
  data.frame(
    chr = as.vector(GenomeInfoDb::seqnames(regA)),
    start = start(regA) + dst,
    end = end(regA) + dst
  )
)

RsetD <- similarRegionSet(
  GR = regD,
  name = "regD",
  genome = gnm,
  vectorPerc = vectorPerc2
)

Rset_NO <- list(reg_no_A, reg_no_B, reg_no_C, reg_no_AB, reg_no_ABC)
names(Rset_NO) <- c("reg_no_A", "reg_no_B", "reg_no_C", "reg_no_AB", "reg_no_ABC")

AlienRSList_narrow <- c(RsetA, RsetB, RsetC, RsetD, RsetAB, Rset_NO)

saveRDS(regA, "A.rds")
saveRDS(AlienRSList_narrow, "Blist.rds")
saveRDS(AlienGenome, "genome.rds")