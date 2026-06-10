# Load the Bioconductor package
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("annotationTools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(annotationTools)

# Reproduce the vignette's data preparation for annotation_HGU133Plus2
# This uses a partial dataset from the package's 'extdata' directory.
annotationFile_HGU133Plus2 <- system.file('extdata','HG-U133_Plus_2_annot_part.csv',
                                          package='annotationTools')
annotation_HGU133Plus2 <- read.csv(annotationFile_HGU133Plus2, colClasses='character',
                                   comment.char='#')

# Reproduce the vignette's data preparation for annotation_Mouse4302
# This also uses a partial dataset from the package's 'extdata' directory.
annotationFile_Mouse4302 <- system.file('extdata','Mouse430_2_annot_part.csv',
                                          package='annotationTools')
annotation_Mouse4302 <- read.csv(annotationFile_Mouse4302, colClasses='character')

# Reproduce the vignette's data preparation for homologene
# This uses a partial dataset from the package's 'extdata' directory.
homologeneFile <- system.file('extdata','homologene_part.data',
                              package='annotationTools')
homologene <- read.delim(homologeneFile, header=FALSE)

# Serialize annotation_HGU133Plus2 to 'HG-U133_Plus_2_annot.csv'
# The workflow reads this with read.csv(..., colClasses='character', comment.char='#').
# write.csv ensures comma separation and quotes strings, matching the read format.
write.csv(annotation_HGU133Plus2, file='HG-U133_Plus_2_annot.csv', row.names=FALSE, quote=TRUE)

# Serialize annotation_Mouse4302 to 'Mouse430_2_annot.csv'
# The workflow reads this with read.csv(..., colClasses='character', comment.char='#').
# write.csv ensures comma separation and quotes strings, matching the read format.
write.csv(annotation_Mouse4302, file='Mouse430_2_annot.csv', row.names=FALSE, quote=TRUE)

# Serialize homologene to 'homologene.data'
# The workflow reads this with read.delim(..., header=FALSE).
# write.table with sep='\t', col.names=FALSE, row.names=FALSE, and quote=FALSE
# ensures the output matches the expected tab-separated, no-header format.
write.table(homologene, file='homologene.data', sep='\t', col.names=FALSE, row.names=FALSE, quote=FALSE)