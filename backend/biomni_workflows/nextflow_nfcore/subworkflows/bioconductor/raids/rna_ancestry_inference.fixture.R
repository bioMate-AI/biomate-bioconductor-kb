library(RAIDS)
library(SNPRelate)
library(gdsfmt)

# 1. demoPedigreeEx1
ped_file <- list.files(system.file("extdata", package="RAIDS"), pattern="demoPedigreeEx1", full.names=TRUE)
if (length(ped_file) > 0) {
    file.copy(ped_file[1], "demoPedigreeEx1")
} else {
    demoPedigreeEx1 <- data.frame(
        Name.ID = c("sample1"),
        Case.ID = c("case1"),
        Sample.Type = c("RNA"),
        Diagnosis = c("Cancer"),
        Source = c("TCGA"),
        stringsAsFactors = FALSE
    )
    saveRDS(demoPedigreeEx1, "demoPedigreeEx1")
}

# 2. studyDF
study_file <- list.files(system.file("extdata", package="RAIDS"), pattern="studyDF", full.names=TRUE)
if (length(study_file) > 0) {
    file.copy(study_file[1], "studyDF")
} else {
    studyDF <- data.frame(
        study.id = "study1",
        study.desc = "Demo Study",
        study.platform = "Illumina",
        stringsAsFactors = FALSE
    )
    saveRDS(studyDF