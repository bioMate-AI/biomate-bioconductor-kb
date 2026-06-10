library(spiky)

# 1. Genomic BEDPE files
genomic_bedpe_src <- system.file("extdata", "example_chr21_bedpe.bed.gz", package="spiky", mustWork=TRUE)
file.copy(genomic_bedpe_src, "genomic_bedpe.bed.gz", overwrite=TRUE)

genomic_bedpe_tbi_src <- system.file("extdata", "example_chr21_bedpe.bed.gz.tbi", package="spiky")
if (genomic_bedpe_tbi_src != "") {
    file.copy(genomic_bedpe_tbi_src, "genomic_bedpe.bed.gz.tbi", overwrite=TRUE)
} else if (file.exists(paste0(genomic_bedpe_src, ".tbi"))) {
    file.copy(paste0(genomic_bedpe_src, ".tbi"), "genomic_bedpe.bed.gz.tbi", overwrite=TRUE)
} else {
    file.create("genomic_bedpe.bed.gz.tbi")
}

# 2. Spike BEDPE files
spike_bedpe_src <- system.file("extdata", "example_spike_bedpe.bed.gz", package="spiky", mustWork=TRUE)
file.copy(spike_bedpe_src, "spike_bedpe.bed.gz", overwrite=TRUE)

spike_bedpe_tbi_src <- system.file("extdata", "example_spike_bedpe.bed.gz.tbi", package="spiky")
if (spike_bedpe_tbi_src != "") {
    file.copy(spike_bedpe_tbi_src, "spike_bedpe.bed.gz.tbi", overwrite=TRUE)
} else if (file.exists(paste0(spike_bedpe_src, ".tbi"))) {
    file.copy(paste0(spike_bedpe_src, ".tbi"), "spike_bedpe.bed.gz.tbi", overwrite=TRUE)
} else {
    file.create("spike_bedpe.bed.gz.tbi")
}

# 3. BAM files (as requested by structured input spec)
genomic_bam_src <- system.file("extdata", "example_chr21.bam", package="spiky", mustWork=TRUE)
file.copy(genomic_bam_src, "genomic_bam", overwrite=TRUE)
if (file.exists(paste0(genomic_bam_src, ".bai"))) {
    file.copy(paste0(genomic_bam_src, ".bai"), "genomic_bam.bai", overwrite=TRUE)
} else {
    file.create("genomic_bam.bai")
}

spike_bam_src <- system.file("extdata", "example.spike.bam", package="spiky", mustWork=TRUE)
file.copy(spike_bam_src, "spike_bam", overwrite=TRUE)
if (file.exists(paste0(spike_bam_src, ".bai"))) {
    file.copy(paste0(spike_bam_src, ".bai"), "spike_bam.bai", overwrite=TRUE)
} else {
    file.create("spike_bam.bai")
}