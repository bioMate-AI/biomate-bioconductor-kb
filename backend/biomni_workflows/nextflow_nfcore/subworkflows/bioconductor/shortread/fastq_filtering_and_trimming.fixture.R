library(ShortRead)

fl <- system.file(package="ShortRead", "extdata", "E-MTAB-1147", "ERR127302_1_subset.fastq.gz")
if (!file.exists(fl) || fl == "") {
    fls <- list.files(system.file("extdata", package="ShortRead"), pattern="\\.fastq(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    fl <- fls[1]
}

fq <- readFastq(fl)
writeFastq(fq, "a.fastq.gz")