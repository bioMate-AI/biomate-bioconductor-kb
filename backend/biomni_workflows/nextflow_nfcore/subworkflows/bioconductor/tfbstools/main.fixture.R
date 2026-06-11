library(TFBSTools)
library(Biostrings)

# 1. Reproduce the vignette's PFMatrix construction
pfm <- PFMatrix(
    ID="MA0004.1", 
    name="Arnt", 
    matrixClass="Zipper-Type", 
    strand="+", 
    bg=c(A=0.25, C=0.25, G=0.25, T=0.25), 
    tags=list(
        family="Helix-Loop-Helix", 
        species="10090", 
        tax_group="vertebrates",
        medline="7592839", 
        type="SELEX",
        ACC="P53762", 
        pazar_tf_id="TF0000003", 
        TFBSshape_ID="11", 
        TFencyclopedia_ID="580"
    ), 
    profileMatrix=matrix(
        c(4L, 19L, 0L, 0L, 0L, 0L, 
          16L, 0L, 20L, 0L, 0L, 0L, 
          0L, 1L, 0L, 20L, 0L, 20L, 
          0L, 0L, 0L, 0L, 20L, 0L), 
        byrow=TRUE, 
        nrow=4, 
        dimnames=list(c("A", "C", "G", "T"))
    )
)

# 2. Serialize the JASPAR ID to pfm_data.txt
writeLines(ID(pfm), "pfm_data.txt")

# 3. Create a DNA sequence containing the Arnt binding motif and write to sequence.fasta
seqs <- DNAStringSet(c(seq1 = "ATGCACGTGCTAGCACGTGATGCACGTGCTAGCACGTG"))
writeXStringSet(seqs, "sequence.fasta")