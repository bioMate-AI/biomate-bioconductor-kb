# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CRImage")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CRImage)

# 1. Reproduce the vignette's data-preparation code for trainingData.txt
# The vignette shows `createTrainingSet` is used to generate the initial feature table.
# It then manually adds 'class' values.
# Note: The vignette uses "exImg.jpg" for createTrainingSet, but system.file("extdata", "exImg.jpg", package="CRImage")
# returns an empty string, indicating it doesn't exist. "exImg2.jpg" is consistently used elsewhere and exists.
# We will use "exImg2.jpg" for createTrainingSet.
img_path_for_training_set = system.file("extdata", "exImg2.jpg", package="CRImage")
trainingValues = createTrainingSet(filename=img_path_for_training_set, maxShape=800, minShape=40, failureRegion=2000)

# The second element of trainingValues is the feature table.
trainingData = trainingValues[[2]]

# As shown in the vignette, class values are then manually inserted.
# We will populate the 'class' column for a few rows to create a minimal training set.
# The vignette example shows 'normal' and 'malignant' classes.
trainingData$class = NA # Initialize class column with NAs
if (nrow(trainingData) >= 1) {
  trainingData$class[1] = "normal"
}
if (nrow(trainingData) >= 2) {
  trainingData$class[2] = "malignant"
}
# Add a few more for a slightly more robust (but still minimal) example,
# ensuring there are enough examples for each class as suggested by the vignette.
if (nrow(trainingData) >= 3) {
  trainingData$class[3] = "normal"
}
if (nrow(trainingData) >= 4) {
  trainingData$class[4] = "malignant"
}
if (nrow(trainingData) >= 5) {
  trainingData$class[5] = "normal"
}

# 2. Serialize the trainingData object to trainingData.txt
# The vignette explicitly mentions `write.table(trainingData,file="path",sep="\t",rownames=F)`
write.table(trainingData, file="trainingData.txt", sep="\t", row.names=FALSE)

# 3. Reproduce the vignette's data-preparation for exImg2.jpg
# The vignette consistently uses `f = system.file("extdata", "exImg2.jpg", package="CRImage")`
# and `img=readImage(f)`. This means exImg2.jpg is an existing file within the package.
# To "generate" this input file for the workflow, we copy it from the package's extdata.
source_img_path = system.file("extdata", "exImg2.jpg", package="CRImage")

# 4. Serialize the exImg2.jpg file to the working directory
file.copy(source_img_path, "exImg2.jpg", overwrite=TRUE)