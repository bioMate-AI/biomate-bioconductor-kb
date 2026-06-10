library(RCAS)

# 1. Define paths to BED files
FUS_rep1_path <- system.file('extdata', 'FUS_Nakaya2013c_hg19.bed', package = 'RCAS')
FUS_rep2_path <- system.file('extdata', 'FUS_Nakaya2013d_hg19.bed', package = 'RCAS')
FMR1_rep1_path <- system.file('extdata', 'FMR1_Ascano2012a_hg19.bed', package = 'RCAS')
FMR1_rep2_path <- system.file('extdata', 'FMR1_Ascano2012b_hg19.bed', package = 'RCAS')
EIF4A3_rep1_path <- system.file('extdata', 'EIF4A3Sauliere20121a.bed', package = 'RCAS')
EIF4A3_rep2_path <- system.file('extdata', 'EIF4A3Sauliere20121b.bed', package = 'RCAS')

# Fallback if specific files are missing in the current package version
if (FUS_rep1_path == "") {
    bed_files <- list.files(system.file("extdata", package="RCAS"), pattern="\\.bed$", full.names=TRUE)
    if (length(bed_files) > 0) {
        FUS_rep1_path <- bed_files[1]
        FUS_rep2_path <- bed_files[min(2, length(bed_files))]
        FMR1_rep1_path <- bed_files[min(3, length(bed_files))]
        FMR1_rep2_path <- bed_files[min(4, length(bed_files))]
        EIF4A3_rep1_path <- bed_files[min(5, length(bed_files))]
        EIF4A3_rep2_path <- bed_files[min(6, length(bed_files))]
    }
}

# Create the project data frame
projData <- data.frame(
  'sampleName' = c('FUS_1', 'FUS_2', 'FMR1_1', 'FMR1_2', 'EIF4A3_1', 'EIF4A3_2'),
  'bedFilePath' = c(FUS_rep1_path, FUS_rep2_path, FMR1_rep1_path, FMR1_rep2_path, EIF4A3_rep1_path, EIF4A3_rep2_path),
  stringsAsFactors = FALSE
)

# Write myProjDataFile.tsv
projDataFile <- file.path(getwd(), 'myProjDataFile.tsv')
write.table(projData, projDataFile, sep = '\t', quote = FALSE, row.names = FALSE)

# 2. Define path to GTF file and copy to annotation.gtf
gtfFilePath <- system.file("extdata", "hg19.sample.gtf", package = "RCAS")
if (gtfFilePath == "") {
    gtf_files <- list.files(system.file("extdata", package="RCAS"), pattern="\\.gtf$", full.names=TRUE)
    if (length(gtf_files) > 0) gtfFilePath <- gtf_files[1]
}
file.copy(gtfFilePath, "annotation.gtf", overwrite = TRUE)

# 3. Create the sample data table
sampleData <- data.frame(
  'sampleName' = c('FUS_1', 'FUS_2', 'EIF4A3_1', 'EIF4A3_2'),
  'sampleGroup' = c('FUS', 'FUS', 'EIF4A3', 'EIF4A3'),
  stringsAsFactors = FALSE
)

# Write mySampleDataTable.tsv
sampleDataFile <- file.path(getwd(), 'mySampleDataTable.tsv')
write.table(sampleData, sampleDataFile, sep = '\t', quote = FALSE, row.names = FALSE)