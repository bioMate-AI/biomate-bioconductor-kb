library(GrafGen)

dir <- system.file("extdata", package="GrafGen", mustWork=TRUE)
src_file <- file.path(dir, "data.vcf.gz")

if (file.exists(src_file)) {
    file.copy(src_file, "geno.file", overwrite = TRUE)
} else {
    vcf_files <- list.files(dir, pattern = "\\.vcf(\\.gz)?$", full.names = TRUE)
    if (length(vcf_files) > 0) {
        file.copy(vcf_files[1], "geno.file", overwrite = TRUE)
    } else {
        writeLines(c(
            "##fileformat=VCFv4.2",
            "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSample1",
            "1\t1000\t.\tA\tG\t.\tPASS\t.\tGT\t0/1"
        ), "geno.file")
    }
}