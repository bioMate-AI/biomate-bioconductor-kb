library(scruff)

# Get paths to the built-in files from the scruff package
v1h1R1 <- system.file("extdata", "vandenBrink_1h1_L001_R1_001.fastq.gz", package = "scruff")
v1h1R2 <- system.file("extdata", "vandenBrink_1h1_L001_R2_001.fastq.gz", package = "scruff")
fasta <- system.file("extdata", "GRCm38_MT.fa", package = "scruff")
gtf <- system.file("extdata", "GRCm38_MT.gtf", package = "scruff")

# Copy files to the expected names in the working directory
file.copy(v1h1R1, "read1Path.fastq.gz", overwrite = TRUE)
file.copy(v1h1R2, "read2Path.fastq.gz", overwrite = TRUE)
file.copy(fasta, "reference.fa", overwrite = TRUE)
file.copy(gtf, "reference.gtf", overwrite = TRUE)

# Load barcodeExample and write to barcode_list.tsv
data(barcodeExample, package = "scruff")
writeLines(barcodeExample, "barcode_list.tsv")