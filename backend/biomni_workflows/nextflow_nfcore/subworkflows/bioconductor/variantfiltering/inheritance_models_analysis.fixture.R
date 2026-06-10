library(VariantFiltering)

vcf_src <- system.file("extdata", "CEUtrio.vcf.bgz", package="VariantFiltering")
ped_src <- system.file("extdata", "CEUtrio.ped", package="VariantFiltering")
tbi_src <- system.file("extdata", "CEUtrio.vcf.bgz.tbi", package="VariantFiltering")

if (file.exists(vcf_src)) {
    file.copy(vcf_src, "CEUtrio.vcf.bgz", overwrite = TRUE)
} else {
    stop("CEUtrio.vcf.bgz not found in VariantFiltering extdata")
}

if (file.exists(ped_src)) {
    file.copy(ped_src, "CEUtrio.ped", overwrite = TRUE)
} else {
    stop("CEUtrio.ped not found in VariantFiltering extdata")
}

if (file.exists(tbi_src)) {
    file.copy(tbi_src, "CEUtrio.vcf.bgz.tbi", overwrite = TRUE)
}