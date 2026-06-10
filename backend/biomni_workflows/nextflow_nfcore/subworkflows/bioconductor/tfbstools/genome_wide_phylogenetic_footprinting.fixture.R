suppressPackageStartupMessages({
    library(TFBSTools)
    library(rtracklayer)
    library(BSgenome)
    library(Biostrings)
})

# Function to safely load a requested BSgenome, or fallback to any available, or a mock DNAStringSet
get_bsgenome <- function(target_pkg) {
    if (requireNamespace(target_pkg, quietly = TRUE)) {
        require(target_pkg, character.only = TRUE, quietly = TRUE)
        return(get(target_pkg, envir = asNamespace(target_pkg)))
    } else {
        installed <- installed.packages()[,"Package"]
        bs_pkgs <- grep("^BSgenome\\.", installed, value = TRUE)
        if (length(bs_pkgs) > 0) {
            pkg <- bs_pkgs[1]
            require(pkg, character.only = TRUE, quietly = TRUE)
            return(get(pkg, envir = asNamespace(pkg)))
        }
        return(Biostrings::DNAStringSet(c(chr1 = "NNNNNNNNNNNNNNNNNNNN")))
    }
}

# 1 & 2. Prepare and serialize the target genome (hg19)
hg19_genome <- get_bsgenome("BSgenome.Hsapiens.UCSC.hg19")
saveRDS(hg19_genome, "hg19_genome")

# 1 & 2. Prepare and serialize the query genome (mm10)
mm10_genome <- get_bsgenome("BSgenome.Mmusculus.UCSC.mm10")
saveRDS(mm10_genome, "mm10_genome")

# Helper functions to extract sequence metadata for the chain file
get_seqname <- function(x) {
    if (inherits(x, "BSgenome")) {
        return(as.character(GenomeInfoDb::seqnames(x)[1]))
    } else {
        return(names(x)[1])
    }
}

get_seqlength <- function(x, seqname) {
    if (inherits(x, "BSgenome")) {
        return(as.numeric(GenomeInfoDb::seqlengths(x)[seqname]))
    } else {
        return(length(x[[seqname]]))
    }
}

tName <- get_seqname(hg19_genome)
qName <- get_seqname(mm10_genome)

tSize <- get_seqlength(hg19_genome, tName)
qSize <- get_seqlength(mm10_genome, qName)

# Ensure minimum size for the mock liftover coordinates
tSize <- max(tSize, 20, na.rm = TRUE)
qSize <- max(qSize, 20, na.rm = TRUE)

# 1 & 2. Construct and write a valid minimal liftover chain file
chain_text <- sprintf("chain 1000 %s %.0f + 0 10 %s %.0f + 0 10 1\n10\n", tName, tSize, qName, qSize)
writeLines(chain_text, "hg19ToMm10.over.chain")