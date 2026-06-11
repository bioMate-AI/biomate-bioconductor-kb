library(ShortRead)

# Find a FASTQ file shipped with ShortRead
extdata_dir <- system.file("extdata", package="ShortRead")
fastq_files <- list.files(extdata_dir, pattern="\\.fastq(\\.gz)?$", recursive=TRUE, full.names=TRUE)

if (length(fastq_files) > 0) {
    # Read the first available FASTQ file
    fq <- readFastq(fastq_files[1])
    
    # Write it to the expected input file
    writeFastq(fq, "a.fastq.gz")
} else {
    # Fallback: write a minimal FASTQ file directly based on vignette examples
    fq_lines <- c(
        "@read1",
        "GTCTGCTGTATCTGTGTCGGCTGTCTCGCGGGACGTCAATGAAGGCCTGGAATGTCACTACCCCCAG",
        "+",
        "HHHHHHHHHHHHHHHHHHHHEBDBB?B:BBGG<DABFEFBDBD@DDECEE3>:?;@@@>?=BAB?##",
        "@read2",
        "CTAGGGCAATCTTTGCAGCAATGAATGCCAATGGCAGTGGCTTTTGAGGCCAGAGCAGACCTTCGGG",
        "+",
        "IIIIHIIIGIIIIIIIHIIIIEGBGHIIIIHGIIIIIHIIIHIIIIIGIIIEGIIGBGE@DDGGGIG",
        "@read3",
        "TGGGCTGTTCCTTCTCACTGTGGCCTGACTAAAATGGCATTAAGAAAGAGTCACGTTTCCCAAGTCT",
        "+",
        "GGHBHGBGGGHHHHDHHHHHHHHHFGHHHHHHHHHHHHHHHHHGHFHHHHHHHHHHHHHH8AGDGGG>"
    )
    gz1 <- gzfile("a.fastq.gz", "w")
    writeLines(fq_lines, gz1)
    close(gz1)
}