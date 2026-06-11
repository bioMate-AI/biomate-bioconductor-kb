library(ASEB)

bg_src <- system.file("extdata", "background_sites.fa", package="ASEB")
if (file.exists(bg_src)) {
    file.copy(bg_src, "background_sites.fa", overwrite = TRUE)
}

pre_src <- system.file("extdata", "predefined_sites.fa", package="ASEB")
if (file.exists(pre_src)) {
    file.copy(pre_src, "predefined_sites.fa", overwrite = TRUE)
}

test_src <- system.file("extdata", "sites_to_test.fa", package="ASEB")
if (file.exists(test_src)) {
    file.copy(test_src, "sites_to_test.fa", overwrite = TRUE)
}