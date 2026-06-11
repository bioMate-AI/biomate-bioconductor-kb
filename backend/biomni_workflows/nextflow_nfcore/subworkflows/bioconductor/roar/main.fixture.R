library(roar)
library(rtracklayer)
library(RNAseqData.HNRNPC.bam.chr14)

# Recreate the exact objects from the vignette
gtf <- system.file("examples", "apa.gtf", package="roar")
bamTreatment <- RNAseqData.HNRNPC.bam.chr14_BAMFILES[seq(5,8)]
bamControl <- RNAseqData.HNRNPC.bam.chr14_BAMFILES[seq(1,3)]

# Serialize the objects to the declared input files
saveRDS(bamTreatment, "bamTreatment")
saveRDS(bamControl, "bamControl")
saveRDS(gtf, "gtf")