library(PhyloProfile)

# Locate the domain_annotation.txt file shipped with the package
domain_file <- list.files(
    system.file("extdata", package = "PhyloProfile"), 
    pattern = "domain_annotation\\.txt$", 
    recursive = TRUE, 
    full.names = TRUE
)

if (length(domain_file) > 0 && file.exists(domain_file[1])) {
    file.copy(domain_file[1], "domain_annotation.txt", overwrite = TRUE)
} else {
    # Fallback: create a synthetic domain_annotation.txt if not found
    domain_data <- data.frame(
        seedID = c("100136at6656", "100136at6656"),
        orthoID = c("100136at6656|PLAF7@36329@1|Q8ILT8|1", "100136at6656|POLVAN@319348@0|319348_0:004132|1"),
        length = c(100, 120),
        feature = c("PF00001", "PF00002"),
        start = c(10, 20),
        end = c(50, 80),
        weight = c(1, 1)
    )
    write.table(domain_data, "domain_annotation.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}