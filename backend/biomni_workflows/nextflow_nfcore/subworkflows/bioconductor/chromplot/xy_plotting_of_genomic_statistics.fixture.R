# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("chromPlot", "qtl")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("chromPlot")
library("qtl")

# Reproduce hg_gap
data(hg_gap)
write.table(hg_gap, file = "hg_gap", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Reproduce hg_cytoBandIdeo
data(hg_cytoBandIdeo)
write.table(hg_cytoBandIdeo, file = "hg_cytoBandIdeo", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Reproduce fst
data_file2 <- system.file("extdata", "Fst_CEU-YRI-W200Chr19-21.bed", package = "chromPlot")
fst  <- read.table(data_file2, sep="\t", stringsAsFactors=FALSE, header=TRUE)
fst$Colors <-
  ifelse(fst$win.FST >= 0     & fst$win.FST  < 0.025, "gray66",
  ifelse(fst$win.FST >= 0.025 & fst$win.FST  < 0.05,  "grey55",
  ifelse(fst$win.FST >= 0.05  & fst$win.FST  < 0.075, "grey35",
  ifelse(fst$win.FST >= 0.075 & fst$win.FST  < 0.1,   "black",
  ifelse(fst$win.FST >= 0.1   & fst$win.FST  < 1,     "red","red")))))
fst$Group <-
  ifelse(fst$win.FST >= 0     & fst$win.FST < 0.025, "Fst 0-0.025",
  ifelse(fst$win.FST >= 0.025 & fst$win.FST < 0.05,  "Fst 0.025-0.05",
  ifelse(fst$win.FST >= 0.05  & fst$win.FST < 0.075, "Fst 0.05-0.075",
  ifelse(fst$win.FST >= 0.075 & fst$win.FST < 0.1,   "Fst 0.075-0.1",
  ifelse(fst$win.FST >= 0.1   & fst$win.FST < 1,     "Fst 0.1-1","na")))))
write.table(fst, file = "fst", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Reproduce ihs
data_file8 <- system.file("extdata", "iHS_CEUChr19-21", package = "chromPlot")
ihs <- read.table(data_file8, sep="\t", stringsAsFactors=FALSE, header=TRUE)
write.table(ihs, file = "ihs", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Reproduce xpehh
data_file9 <-system.file("extdata", "XPEHH_CEU-YRIChr19-21", package="chromPlot")
xpehh <-read.table(data_file9, sep="\t", stringsAsFactors=FALSE, header=TRUE)
xpehh$ID <- ""
xpehh[which.max(xpehh$XP),"ID"] <- xpehh[which.max(xpehh$XP),"Name"]
write.table(xpehh, file = "xpehh", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Reproduce QTLs
data(hyper)
hyper <- calc.genoprob(hyper, step=1)
hyper <- scanone(hyper)
QTLs <- hyper
colnames(QTLs) <- c("Chrom", "cM", "LOD")
QTLs$Start <- 1732273 + QTLs$cM * 1895417
write.table(QTLs, file = "QTLs", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)