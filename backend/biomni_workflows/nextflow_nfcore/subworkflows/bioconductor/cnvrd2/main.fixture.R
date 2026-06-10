# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVrd2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library('CNVrd2')

data(fcgr3bMXL)

readCountMatrix <- resultSegment$stdCntMatrix

objectCNVrd2 <- new("CNVrd2", windows = 1000, chr = "chr1",
                    st = 161100001, en = 162100000,
                    dirBamFile = "BamMXL",
                    genes = c(161592986, 161601753),
                    geneNames = "3B")

resultSegment <- segmentSamples(Object = objectCNVrd2, stdCntMatrix = readCountMatrix)

objectCluster <- new("clusteringCNVs",
                     x = resultSegment$segmentationScores[, 1], k = 4, EV = TRUE)

copynumberGroups <- groupCNVs(Object = objectCluster)

sampleCNV <- data.frame(copynumberGroups$allGroups[, c(1,2) ],
                        rep("MXL", dim(copynumberGroups$allGroups)[1]))
rownames(sampleCNV) <- substr(sampleCNV[, 1], 1, 7)
sampleCNV[, 1] <- rownames(sampleCNV)

saveRDS(objectCNVrd2, "BamMXL")

vcfFile_source <- system.file(package="CNVrd2", "extdata",
                              "chr1.161600000.161611000.vcf.gz")

file.copy(from = vcfFile_source,
          to = "chr1.161600000.161611000.vcf.gz",
          overwrite = TRUE)

write.csv(sampleCNV, "sampleCNV.csv", row.names = FALSE)