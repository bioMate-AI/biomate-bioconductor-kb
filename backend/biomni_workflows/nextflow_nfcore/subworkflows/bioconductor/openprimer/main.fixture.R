library(openPrimeR)

# Find and copy templates.fasta
fasta_candidates <- list.files(system.file("extdata", package="openPrimeR"), 
                               pattern="Homo_sapiens_IGH_functional_exon.fasta", 
                               recursive=TRUE, full.names=TRUE)
if (length(fasta_candidates) > 0) {
    file.copy(fasta_candidates[1], "templates.fasta", overwrite = TRUE)
} else {
    stop("Could not find Homo_sapiens_IGH_functional_exon.fasta")
}

# Find and copy leader.fasta
leader_candidates <- list.files(system.file("extdata", package="openPrimeR"), 
                                pattern="Homo_sapiens_IGH_functional_leader.fasta", 
                                recursive=TRUE, full.names=TRUE)
if (length(leader_candidates) > 0) {
    file.copy(leader_candidates[1], "leader.fasta", overwrite = TRUE)
} else {
    stop("Could not find Homo_sapiens_IGH_functional_leader.fasta")
}

# Find and copy settings.xml
settings_candidates <- list.files(system.file("extdata", package="openPrimeR"), 
                                  pattern="C_Taq_PCR_high_stringency.xml", 
                                  recursive=TRUE, full.names=TRUE)
if (length(settings_candidates) > 0) {
    file.copy(settings_candidates[1], "settings.xml", overwrite = TRUE)
} else {
    stop("Could not find C_Taq_PCR_high_stringency.xml")
}