library(MungeSumstats)

# Attempt to locate the actual file shipped with the package
pkg_file <- list.files(
    system.file("extdata", package = "MungeSumstats"), 
    pattern = "eduAttainOkbay\\.txt", 
    recursive = TRUE, 
    full.names = TRUE
)

if (length(pkg_file) > 0 && file.exists(pkg_file[1])) {
    # Copy the existing file to the working directory
    file.copy(pkg_file[1], "eduAttainOkbay.txt", overwrite = TRUE)
} else {
    # Construct a synthetic GWAS summary statistics file if not found
    # using standard columns expected by MungeSumstats
    synthetic_sumstats <- data.frame(
        SNP = c("rs3131972", "rs3131969", "rs3131967"),
        CHR = c(1, 1, 1),
        BP = c(752721, 754182, 754334),
        A1 = c("A", "A", "T"),
        A2 = c("G", "G", "C"),
        P = c(0.5, 0.1, 0.05),
        BETA = c(0.02, -0.05, 0.1),
        SE = c(0.01, 0.02, 0.01),
        N = c(10000, 10000, 10000)
    )
    
    write.table(
        synthetic_sumstats, 
        file = "eduAttainOkbay.txt", 
        sep = "\t", 
        row.names = FALSE, 
        quote = FALSE
    )
}