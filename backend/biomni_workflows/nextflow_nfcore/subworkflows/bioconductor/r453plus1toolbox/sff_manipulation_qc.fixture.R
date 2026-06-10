library(R453Plus1Toolbox)

# Locate the example SFF file shipped with the package
example_sff <- system.file("extdata", "SFF", "example.sff", package="R453Plus1Toolbox")

# Copy it to the working directory as the expected input file named 'file'
file.copy(example_sff, "file", overwrite = TRUE)