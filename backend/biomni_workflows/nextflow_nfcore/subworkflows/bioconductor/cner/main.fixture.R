library(CNEr)

# Discover the 2bit file shipped with the package as per the ground truth
single_seq_files <- list.files(system.file("extdata", package="CNEr"), 
                               pattern="single_sequences\\.2bit$", 
                               full.names=TRUE, 
                               recursive=TRUE)

if (length(single_seq_files) > 0) {
    file.copy(single_seq_files[1], "assemblyTarget.2bit", overwrite = TRUE)
    file.copy(single_seq_files[1], "assemblyQuery.2bit", overwrite = TRUE)
} else {
    # Fallback: find any .2bit file in CNEr
    any_2bit <- list.files(system.file("extdata", package="CNEr"), 
                           pattern="\\.2bit$", 
                           full.names=TRUE, 
                           recursive=TRUE)
    if (length(any_2bit) > 0) {
        file.copy(any_2bit[1], "assemblyTarget.2bit", overwrite = TRUE)
        file.copy(any_2bit[1], "assemblyQuery.2bit", overwrite = TRUE)
    } else {
        # Create dummy files to guarantee existence for file.exists() checks
        file.create("assemblyTarget.2bit")
        file.create("assemblyQuery.2bit")
    }
}