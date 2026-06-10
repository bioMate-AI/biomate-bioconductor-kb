# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CRImage")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CRImage)

# --- Generate trainingData.txt ---
# 1. Get the path to an example image for creating the training set
f_training_img <- system.file("extdata", "exImg.jpg", package="CRImage")

# 2. Create the initial training set values using the vignette's parameters
trainingValues <- createTrainingSet(
    filename = f_training_img,
    maxShape = 800,
    minShape = 40,
    failureRegion = 2000
)

# 3. Extract the feature table, which is the second element of the list
trainingData <- trainingValues[[2]]

# 4. Assign class values as shown in the vignette example
# The vignette shows assigning 'normal' to the first row and 'malignant' to the second.
# We ensure these rows exist before assigning.
if (nrow(trainingData) >= 1) {
    trainingData$class[1] <- "normal"
}
if (nrow(trainingData) >= 2) {
    trainingData$class[2] <- "malignant"
}

# 5. Save the modified table to "trainingData.txt" in the working directory.
# Use tab separator and no row names, matching the workflow's read.table.
# quote=FALSE ensures string values like "normal" are not enclosed in quotes.
write.table(
    trainingData,
    file = "trainingData.txt",
    sep = "\t",
    row.names = FALSE,
    quote = FALSE
)

# --- Generate inputFolder ---
# 1. Create the "inputFolder" directory in the working directory.
# showWarnings = FALSE prevents warnings if the directory already exists.
dir.create("inputFolder", showWarnings = FALSE)

# 2. Get the path to an example image from the CRImage package's extdata.
# exImg2.jpg is frequently used in the vignette for classification and segmentation.
f_input_img <- system.file("extdata", "exImg2.jpg", package="CRImage")

# 3. Copy the example image into the newly created "inputFolder".
file.copy(f_input_img, "inputFolder")