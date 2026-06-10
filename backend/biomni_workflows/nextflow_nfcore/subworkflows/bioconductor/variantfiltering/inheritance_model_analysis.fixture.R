library(VariantFiltering)

vcf_src <- system.file("extdata", "CEUtrio.vcf.bgz", package="VariantFiltering")
if (file.exists(vcf_src)) {
    file.copy(vcf_src, "CEUtrio.vcf.bgz", overwrite = TRUE)
}

tbi_src <- system.file("extdata", "CEUtrio.vcf.bgz.tbi", package="VariantFiltering")
if (file.exists(tbi_src)) {
    file.copy(tbi_src, "CEUtrio.vcf.bgz.tbi", overwrite = TRUE)
}

ped_src <- system.file("extdata", "CEUtrio.ped", package="VariantFiltering")
if (file.exists(ped_src)) {
    file.copy(ped_src, "CEUtrio.ped", overwrite = TRUE)
}