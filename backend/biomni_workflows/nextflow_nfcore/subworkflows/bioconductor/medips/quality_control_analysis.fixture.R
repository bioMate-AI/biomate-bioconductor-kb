library(MEDIPS)
library(MEDIPSData)

# The vignette uses BAM files provided by the MEDIPSData package.
# We locate the specific BAM file used in the vignette.
bam_source <- system.file("extdata", "hESCs.MeDIP.Rep1.chr22.bam", package="MEDIPSData")

# Copy the BAM file to the working directory using the exact requested input filename
file.copy(bam_source, "bam.file.hESCs.Rep1.MeDIP", overwrite = TRUE)

# Also copy it using its original basename to ensure it is available if referenced by its actual filename
file.copy(bam_source, basename(bam_source), overwrite = TRUE)