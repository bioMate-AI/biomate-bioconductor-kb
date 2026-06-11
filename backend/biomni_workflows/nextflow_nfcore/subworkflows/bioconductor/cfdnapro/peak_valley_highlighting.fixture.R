library(cfDNAPro)

# Get the path to the example sample from the package
exam_path_source <- examplePath("step6")

# Create the target directory in the working directory
dir.create("exam_path", showWarnings = FALSE, recursive = TRUE)

# Copy the contents to the target directory
files_to_copy <- list.files(exam_path_source, full.names = TRUE)
file.copy(files_to_copy, "exam_path", recursive = TRUE)