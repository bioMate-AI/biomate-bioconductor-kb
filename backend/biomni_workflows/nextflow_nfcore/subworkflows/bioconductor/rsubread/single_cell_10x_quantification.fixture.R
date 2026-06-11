library(Rsubread)

# 1. Generate hg38_chr1.fa.gz (FASTA reference genome)
fa_content <- c(">chr1", paste(rep("A", 10000), collapse=""))
gz1 <- gzfile("hg38_chr1.fa.gz", "w")
writeLines(fa_content, gz1)
close(gz1)

# 2. Generate reads_R1.fastq.gz (Barcode/UMI file) and reads_R2.fastq.gz (Read file)
n_reads <- 100
set.seed(123)

r1_lines <- character(n_reads * 4)
r2_lines <- character(n_reads * 4)

for(i in 1:n_reads) {
  # 16bp barcode + 12bp UMI
  umi <- paste0(sample(c("A","C","G","T"), 12, replace=TRUE), collapse="")
  
  r1_lines[(i-1)*4 + 1] <- paste0("@read", i)
  r1_lines[(i-1)*4 + 2] <- paste0("ACGTACGTACGTACGT", umi)
  r1_lines[(i-1)*4 + 3] <- "+"
  r1_lines[(i-1)*4 + 4] <- paste(rep("I", 28), collapse="")
  
  # 98bp transcript read
  r2_lines[(i-1)*4 + 1] <- paste0("@read", i)
  r2_lines[(i-1)*4 + 2] <- paste(rep("A", 98), collapse="")
  r2_lines[(i-1)*4 + 3] <- "+"
  r2_lines[(i-1)*4 + 4] <- paste(rep("I", 98), collapse="")
}

gz2 <- gzfile("reads_R1.fastq.gz", "w")
writeLines(r1_lines, gz2)
close(gz2)

gz3 <- gzfile("reads_R2.fastq.gz", "w")
writeLines(r2_lines, gz3)
close(gz3)