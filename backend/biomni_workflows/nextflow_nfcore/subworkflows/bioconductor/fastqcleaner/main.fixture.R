library("FastqCleaner")
library("Biostrings")
library("ShortRead")

# create sequences
set.seed(15)
input <- random_seq(6, 43)

# create qualities of width 50
set.seed(10)
input_q <- random_qual(c(30, 40), slength = 6, swidth = 50, encod = "Sanger")

# create names
input_names <- seq_names(length(input))

### FULL ADAPTER IN 3'
adapter <- "ATCGACT"
# Create sequences with adapter
my_seqs <- paste0(input, adapter)
my_seqs <- DNAStringSet(my_seqs)

# create ShortReadQ object
my_read <- ShortReadQ(sread = my_seqs, quality = input_q, id = input_names)

# Write to the expected input file
writeFastq(my_read, "example_fastq.gz", compress = TRUE)