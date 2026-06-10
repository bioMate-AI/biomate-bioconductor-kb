library(PhyloProfile)

rawInput <- system.file("extdata", "test.main.long", package = "PhyloProfile")

if (file.exists(rawInput)) {
    file.copy(rawInput, "raw_profile.txt", overwrite = TRUE)
} else {
    data("mainLongRaw", package = "PhyloProfile")
    write.table(
        mainLongRaw, 
        file = "raw_profile.txt", 
        sep = "\t", 
        quote = FALSE, 
        row.names = FALSE
    )
}