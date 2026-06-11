library(mitoClone2)

# Load and save M_P1
m_file <- system.file("data/M_P1.RData", package = "mitoClone2")
if (file.exists(m_file)) {
    load(m_file)
} else {
    data("M_P1", package = "mitoClone2")
}
save(M_P1, file = "M_P1.RData")

# Load and save N_P1
n_file <- system.file("data/N_P1.RData", package = "mitoClone2")
if (file.exists(n_file)) {
    load(n_file)
} else {
    data("N_P1", package = "mitoClone2")
}
save(N_P1, file = "N_P1.RData")