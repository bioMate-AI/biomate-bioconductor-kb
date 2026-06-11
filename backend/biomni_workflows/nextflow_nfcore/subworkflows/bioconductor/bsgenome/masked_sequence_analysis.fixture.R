library(BSgenome)
library(BSgenome.Hsapiens.UCSC.hg38.masked)

# The workflow expects an input named BSgenome.Hsapiens.UCSC.hg38.masked.
# Since it is a Bioconductor package but the test harness expects a file in the working directory,
# we serialize the genome object to a file with the exact required name.
saveRDS(BSgenome.Hsapiens.UCSC.hg38.masked, "BSgenome.Hsapiens.UCSC.hg38.masked")