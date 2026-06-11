library(cfdnakit)

# Attempt to locate a ready-made SampleFragment RDS file from the package
sf_file <- system.file("extdata", "example_patientcfDNA_SampleFragment.RDS", package = "cfdnakit")

if (sf_file == "" || !file.exists(sf_file)) {
    # Fallback 1: Any SampleFragment RDS
    candidate_files <- list.files(system.file("extdata", package="cfdnakit"), pattern="(?i)SampleFragment.*\\.rds$", full.names=TRUE)
    if (length(candidate_files) > 0) {
        sf_file <- candidate_files[1]
    } else {
        # Fallback 2: Generate from a SampleBam RDS
        sb_files <- list.files(system.file("extdata", package="cfdnakit"), pattern="(?i)SampleBam.*\\.rds$", full.names=TRUE)
        if (length(sb_files) > 0) {
            sb <- readRDS(sb_files[1])
            sf <- get_fragment_profile(sb, sample_id = "Healthy.1")
            sf_file <- "dummy_SampleFragment.rds"
            saveRDS(sf, sf_file)
        } else {
            # Fallback 3: Generate from a BAM file
            bam_files <- list.files(system.file("extdata", package="cfdnakit"), pattern="(?i)\\.bam$", full.names=TRUE)
            if (length(bam_files) > 0) {
                sb <- read_bamfile(bam_files[1], apply_blacklist = FALSE)
                sf <- get_fragment_profile(sb, sample_id = "Healthy.1")
                sf_file <- "dummy_SampleFragment.rds"
                saveRDS(sf, sf_file)
            } else {
                # Fallback 4: Create a synthetic mock object based on vignette structure
                sf <- list(sample_profile = data.frame(
                    Sample.ID = "Healthy.1",
                    Total.Fragments = 68094,
                    Read.Pairs.in.range = 65421,
                    Read.Pairs.in.range..corrected. = 62091.41,
                    N.Short = 23503,
                    N.Long = 41918,
                    Mode = 167,
                    Median = 159,
                    Mean = 163.23,
                    Mad = 20.76,
                    S.L.Ratio = 0.56,
                    S.L.Ratio_corrected = 0.56,
                    Bin.Size.KB. = 1000
                ))
                class(sf) <- "SampleFragment"
                sf_file <- "dummy_SampleFragment.rds"
                saveRDS(sf, sf_file)
            }
        }
    }
}

# Create multiple copies to simulate a Panel of Normals (PoN)
pon_files <- c("SampleFragment_healthyplasma-01.rds", 
               "SampleFragment_healthyplasma-02.rds", 
               "SampleFragment_healthyplasma-03.rds")

for (pf in pon_files) {
    file.copy(sf_file, pf, overwrite = TRUE)
}

# Write the expected input file containing the paths
writeLines(pon_files, "Pon-list.txt")