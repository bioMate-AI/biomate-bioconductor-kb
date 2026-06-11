library(tximeta)
library(tximportData)

dir <- system.file("extdata/salmon_dm", package="tximportData")
files <- file.path(dir, "SRR1197474", "quant.sf")
coldata <- data.frame(files, names="SRR1197474", condition="A", stringsAsFactors=FALSE)

indexDir <- file.path(dir, "Dm.BDGP6.22.98_salmon-0.14.1")
gtfPath <- file.path(dir, "Drosophila_melanogaster.BDGP6.22.98.gtf.gz")

# 1. quant.sf
if (file.exists(files)) {
    file.copy(files, "quant.sf", overwrite = TRUE)
} else {
    writeLines(c("Name\tLength\tEffectiveLength\tTPM\tNumReads", 
                 "FBtr0070129\t100\t100\t10\t100"), "quant.sf")
}

# 2. custom_annotation.gtf.gz
if (file.exists(gtfPath)) {
    file.copy(gtfPath, "custom_annotation.gtf.gz", overwrite = TRUE)
} else {
    gz1 <- gzfile("custom_annotation.gtf.gz", "w")
    writeLines(c('X\tEnsembl\ttranscript\t656673\t657899\t.\t+\t.\tgene_id "FBgn0025637"; transcript_id "FBtr0070129";'), gz1)
    close(gz1)
}

# 3. custom_transcriptome.fa.gz
gz2 <- gzfile("custom_transcriptome.fa.gz", "w")
writeLines(c(">FBtr0070129", "ATGC"), gz2)
close(gz2)