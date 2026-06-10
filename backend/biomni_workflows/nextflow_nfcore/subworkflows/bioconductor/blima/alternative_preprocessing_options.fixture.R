# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("blima", "blimaTestingData", "Biobase", "illuminaHumanv4.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(blima)
library(blimaTestingData)
library(Biobase)
library(illuminaHumanv4.db)

# Data preparation for negAdr
data(blimatesting) # Ensure blimatesting is loaded for context, though not directly used for negAdr here
adrToIllumina = toTable(illuminaHumanv4ARRAYADDRESS)
adrToIllumina = adrToIllumina[, c("ArrayAddress", "IlluminaID")]
colnames(adrToIllumina) = c("Array_Address_Id", "Probe_Id")
illuminaToSymbol = toTable(illuminaHumanv4SYMBOLREANNOTATED)
adrToSymbol = merge(adrToIllumina, illuminaToSymbol, by.x="Probe_Id", by.y="IlluminaID")
adrToSymbol = adrToSymbol[,c("Array_Address_Id", "SymbolReannotated")]
colnames(adrToSymbol) = c("Array_Address_Id", "Symbol")
negIl = mappedLkeys(revmap(illuminaHumanv4REPORTERGROUPNAME)["negative"])
negAdr = mappedRkeys(illuminaHumanv4ARRAYADDRESS[negIl])

# Data preparation for blimatestingall
# The vignette reloads blimatesting here, so we do the same to ensure a clean start
data("blimatesting")
groups1 = "A";
groups2 = "E";
sampleNames = list()
groups1Mod = list()
groups2Mod = list()
processingMod = list()
for(i in 1:length(blimatesting))
{
	p = pData(blimatesting[[i]]@experimentData$phenoData)
	groups1Mod[[i]] = p$Group %in% groups1;
	groups2Mod[[i]] = p$Group %in% groups2;
	processingMod[[i]] = p$Group %in% c(groups1, groups2);
	sampleNames[[i]] = p$Name
}

blimatesting = bacgroundCorrect(blimatesting, normalizationMod = processingMod,
		channelBackgroundFilter="bgf")
blimatesting = nonPositiveCorrect(blimatesting, normalizationMod = processingMod,
		channelCorrect="GrnF",  channelBackgroundFilter="bgf", channelAndVector="bgf")
blimatesting = varianceBeadStabilise(blimatesting, normalizationMod = processingMod,
		quality="GrnF", channelInclude="bgf", channelOutput="vst")
blimatesting = quantileNormalize(blimatesting, normalizationMod = processingMod,
		channelNormalize="vst", channelOutput="qua", channelInclude="bgf")

# The workflow expects an object named 'blimatestingall', which is the result of
# processing 'blimatesting' in the vignette.
blimatestingall <- blimatesting

# Serialize the objects to .rds files
saveRDS(blimatestingall, "blimatestingall.rds")
saveRDS(negAdr, "negAdr.rds")