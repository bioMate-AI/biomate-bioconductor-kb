library(ddCt)
library(Biobase)

# 1. Experiment1.txt
exp_file <- system.file("extdata", "Experiment1.txt", package="ddCt")
if (file.exists(exp_file)) {
    file.copy(exp_file, "Experiment1.txt", overwrite = TRUE)
} else {
    # Fallback to find any txt file in extdata if exact name is missing
    txt_files <- list.files(system.file("extdata", package="ddCt"), pattern="\\.txt$", full.names=TRUE)
    if (length(txt_files) > 0) {
        file.copy(txt_files[1], "Experiment1.txt", overwrite = TRUE)
    } else {
        stop("Could not find Experiment1.txt or any .txt file in ddCt extdata")
    }
}

# 2. ddCt.conf
conf_file <- system.file("scripts", "ddCt.conf", package="ddCt")
if (file.exists(conf_file)) {
    file.copy(conf_file, "ddCt.conf", overwrite = TRUE)
} else {
    # Fallback to create a dummy conf file
    cat("loadPath=.\nsavePath=.\n", file="ddCt.conf")
}

# 3. SampleAnno.txt
anno_file <- system.file("extdata", "SampleAnno.txt", package="ddCt")
if (file.exists(anno_file)) {
    file.copy(anno_file, "SampleAnno.txt", overwrite = TRUE)
} else {
    # Generate SampleAnno.txt based on the samples present in Experiment1.txt
    if (file.exists("Experiment1.txt")) {
        CtData <- SDMFrame("Experiment1.txt")
        samples <- sampleNames(CtData)
        anno_df <- data.frame(
            Sample = samples,
            Condition = rep(c("Control", "Treated"), length.out = length(samples))
        )
        write.table(anno_df, "SampleAnno.txt", sep="\t", row.names=FALSE, quote=FALSE)
    } else {
        anno_df <- data.frame(Sample=c("Sample1", "Sample2"), Condition=c("Control", "Treated"))
        write.table(anno_df, "SampleAnno.txt", sep="\t", row.names=FALSE, quote=FALSE)
    }
}