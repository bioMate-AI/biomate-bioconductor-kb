library(ExiMiR)
library(limma)

# Create a synthetic RGList object as expected by the workflow
set.seed(123)
n_probes <- 100
n_samples <- 4

RG <- new("RGList", list(
  R = matrix(runif(n_probes * n_samples, 100, 10000), n_probes, n_samples),
  G = matrix(runif(n_probes * n_samples, 100, 10000), n_probes, n_samples),
  Rb = matrix(runif(n_probes * n_samples, 10, 100), n_probes, n_samples),
  Gb = matrix(runif(n_probes * n_samples, 10, 100), n_probes, n_samples)
))

# Add some spike-in probes to match ExiMiR's expected behavior
probe_names <- paste0("Probe_", 1:n_probes)
probe_names[1:5] <- paste0("SpikeIn_", 1:5)
rownames(RG$R) <- probe_names
rownames(RG$G) <- probe_names
rownames(RG$Rb) <- probe_names
rownames(RG$Gb) <- probe_names

RG$genes <- data.frame(
  ID = probe_names,
  Name = probe_names,
  stringsAsFactors = FALSE
)

# Save the RGList object to the required input file
saveRDS(RG, "RGList")