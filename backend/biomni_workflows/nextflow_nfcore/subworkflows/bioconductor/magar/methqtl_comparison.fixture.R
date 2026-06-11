suppressPackageStartupMessages(library(MAGAR))

# Copy the reduced_methQTL input directory/file from the package's extdata
reduced_path <- system.file("extdata", "reduced_methQTL", package="MAGAR")
if (file.exists(reduced_path)) {
    file.copy(reduced_path, ".", recursive = TRUE)
}

# Copy or generate the MethQTLResult_chr18 input
res_path <- system.file("extdata", "MethQTLResult_chr18", package="MAGAR")
if (file.exists(res_path)) {
    file.copy(res_path, ".", recursive = TRUE)
} else {
    # Generate it using the vignette's logic if it's not shipped directly
    imp.data <- loadMethQTLInput("reduced_methQTL")
    qtlSetOption(standard.deviation.gauss=100, cluster.cor.threshold=0.75)
    meth.qtl.res <- doMethQTL(imp.data, default.options=FALSE, p.val.cutoff=0.05)
    
    # Save the result using the package's save function if available, else fallback to saveRDS
    if ("saveMethQTLResult" %in% getNamespaceExports("MAGAR")) {
        saveMethQTLResult(meth.qtl.res, "MethQTLResult_chr18")
    } else {
        saveRDS(meth.qtl.res, "MethQTLResult_chr18")
    }
}