library(MetaPhOR)

# The workflow expects BRCA_DEGS.csv in the working directory.
# We copy it from the package's extdata directory.
input_file <- system.file("extdata", "BRCA_DEGS.csv", package = "MetaPhOR")

if (file.exists(input_file)) {
    file.copy(input_file, "BRCA_DEGS.csv", overwrite = TRUE)
} else {
    # Fallback: create a synthetic one based on the vignette's exampledegs.csv structure
    # if the exact file is missing in the installed version.
    example_file <- system.file("extdata", "exampledegs.csv", package = "MetaPhOR")
    if (file.exists(example_file)) {
        file.copy(example_file, "BRCA_DEGS.csv", overwrite = TRUE)
    } else {
        # Synthetic data matching the expected format
        df <- data.frame(
            X = c("TATDN1", "ZNF706", "DCAF13", "TRMT12", "IGF2BP1", "MAP6D1"),
            logFC = c(0.0996779, 0.1055866, 0.0882855, 0.1093866, 0.9256589, 0.1619178),
            AveExpr = c(6.112478, 6.446976, 6.393943, 6.071099, 4.454204, 5.719428),
            t = c(6.074387, 5.845307, 5.513711, 5.434470, 5.631783, 5.342911),
            P.Value = c(0, 0, 1e-07, 1e-07, 0, 1e-07),
            adj.P.Val = c(0.0000523, 0.0000958, 0.0002918, 0.0003550, 0.0002065, 0.0004612),
            B = c(10.736686, 9.237467, 7.531541, 7.377948, 7.273836, 7.090578)
        )
        write.csv(df, "BRCA_DEGS.csv", row.names = FALSE)
    }
}