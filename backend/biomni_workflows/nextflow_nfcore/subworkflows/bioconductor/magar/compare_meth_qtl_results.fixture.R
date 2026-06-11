suppressPackageStartupMessages(library(MAGAR))

# Load the reduced input data shipped with the package
imp.data <- loadMethQTLInput(system.file("extdata", "reduced_methQTL", package="MAGAR"))

# Set options as described in the vignette
qtlSetOption(standard.deviation.gauss=100, cluster.cor.threshold=0.75)

# Compute methQTLs
meth.qtl.res <- doMethQTL(imp.data, default.options=FALSE, p.val.cutoff=0.05)

# Save the resulting methQTLResult object to the expected input files
# Use saveMethQTLResult if available, otherwise fallback to saveRDS
if (exists("saveMethQTLResult", where = asNamespace("MAGAR"), mode = "function")) {
    saveMethQTLResult(meth.qtl.res, "meth.qtl.res")
    saveMethQTLResult(meth.qtl.res, "MethQTLResult_chr18")
} else {
    saveRDS(meth.qtl.res, "meth.qtl.res")
    saveRDS(meth.qtl.res, "MethQTLResult_chr18")
}