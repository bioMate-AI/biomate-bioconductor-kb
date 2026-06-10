library(NetSAM)

input_file <- system.file("extdata", "exampleNetwork.net", package="NetSAM")

if (file.exists(input_file)) {
    file.copy(input_file, "network.net", overwrite = TRUE)
} else {
    # Fallback: create a small synthetic network.net if the package file is missing
    cat("NodeA\tNodeB\nNodeB\tNodeC\nNodeC\tNodeA\n", file="network.net")
}