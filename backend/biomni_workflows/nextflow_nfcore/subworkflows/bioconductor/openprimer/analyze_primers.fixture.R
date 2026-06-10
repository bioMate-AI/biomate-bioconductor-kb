library(openPrimeR)

# 1. templates.fasta
fasta.file <- list.files(system.file("extdata", package = "openPrimeR"), 
                         pattern = "Homo_sapiens_IGH_functional_exon\\.fasta$", 
                         recursive = TRUE, full.names = TRUE)[1]
if (!is.na(fasta.file) && file.exists(fasta.file)) {
    file.copy(fasta.file, "templates.fasta", overwrite = TRUE)
} else {
    stop("Could not find Homo_sapiens_IGH_functional_exon.fasta")
}

# 2. primers.fasta
primer.file <- list.files(system.file("extdata", package = "openPrimeR"), 
                          pattern = "Ippolito2012\\.fasta$", 
                          recursive = TRUE, full.names = TRUE)[1]
if (!is.na(primer.file) && file.exists(primer.file)) {
    file.copy(primer.file, "primers.fasta", overwrite = TRUE)
} else {
    stop("Could not find Ippolito2012.fasta")
}

# 3. settings.xml
settings.file <- list.files(system.file("extdata", package = "openPrimeR"), 
                            pattern = "C_Taq_PCR_high_stringency\\.xml$", 
                            recursive = TRUE, full.names = TRUE)[1]
if (!is.na(settings.file) && file.exists(settings.file)) {
    file.copy(settings.file, "settings.xml", overwrite = TRUE)
} else {
    stop("Could not find C_Taq_PCR_high_stringency.xml")
}