library(Mergeomics)

extdata_dir <- system.file("extdata", package="Mergeomics")

genes_src <- list.files(extdata_dir, pattern="genes\\.hdlc.*\\.txt$", full.names=TRUE)[1]
if (!is.na(genes_src) && file.exists(genes_src)) {
    file.copy(genes_src, "genes.txt", overwrite=TRUE)
} else {
    write.table(data.frame(GENE=c("GENE1", "GENE2"), MARKER=c("rs1", "rs2")), 
                "genes.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

marker_src <- list.files(extdata_dir, pattern="marker\\.hdlc.*\\.txt$", full.names=TRUE)[1]
if (!is.na(marker_src) && file.exists(marker_src)) {
    file.copy(marker_src, "marker.txt", overwrite=TRUE)
} else {
    write.table(data.frame(MARKER=c("rs1", "rs2"), VALUE=c(2.5, 3.1)), 
                "marker.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

modules_src <- list.files(extdata_dir, pattern="modules\\.mousecoexpr.*\\.txt$", full.names=TRUE)[1]
if (!is.na(modules_src) && file.exists(modules_src)) {
    file.copy(modules_src, "modules.txt", overwrite=TRUE)
} else {
    write.table(data.frame(MODULE=c("MOD1", "MOD1"), GENE=c("GENE1", "GENE2")), 
                "modules.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

coexpr_src <- list.files(extdata_dir, pattern="coexpr\\.info\\.txt$", full.names=TRUE)[1]
if (!is.na(coexpr_src) && file.exists(coexpr_src)) {
    file.copy(coexpr_src, "coexpr.info.txt", overwrite=TRUE)
} else {
    write.table(data.frame(MODULE=c("MOD1"), SOURCE=c("Coexpr"), DESCR=c("Test Module")), 
                "coexpr.info.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

network_src <- list.files(extdata_dir, pattern="network\\.mouseliver.*\\.txt$", full.names=TRUE)[1]
if (!is.na(network_src) && file.exists(network_src)) {
    file.copy(network_src, "network.txt", overwrite=TRUE)
} else {
    write.table(data.frame(HEAD=c("GENE1"), TAIL=c("GENE2"), WEIGHT=c(0.8)), 
                "network.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

symbols_src <- list.files(extdata_dir, pattern="symbols\\.txt$", full.names=TRUE)[1]
if (!is.na(symbols_src) && file.exists(symbols_src)) {
    file.copy(symbols_src, "symbols.txt", overwrite=TRUE)
} else {
    write.table(data.frame(HUMAN=c("GENE1", "GENE2"), MOUSE=c("Gene1", "Gene2")), 
                "symbols.txt", sep="\t", row.names=FALSE, quote=FALSE)
}