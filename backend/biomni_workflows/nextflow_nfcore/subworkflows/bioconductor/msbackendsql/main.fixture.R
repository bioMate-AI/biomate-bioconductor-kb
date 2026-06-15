# Real user-style input for MsBackendSql: an mzML file containing MS spectra.
# A user normally obtains mzML from their instrument vendor conversion
# (ProteoWizard msconvert). Here we synthesise a small but genuine set of MS1
# spectra (real m/z + intensity peak lists with retention times) and export
# them to a standards-compliant mzML via the Spectra/mzR writer -- the exact
# file format MsBackendSql::createMsBackendSqlDatabase() consumes. No package
# demo data is used.

suppressPackageStartupMessages({
  library(Spectra)
})

set.seed(11)
n_spectra <- 12
rt <- sort(runif(n_spectra, 30, 600))          # retention times in seconds

# Build a peaks list: each spectrum is a set of m/z / intensity pairs
mk_peaks <- function() {
    k <- sample(8:20, 1)
    mz <- sort(runif(k, 100, 1000))
    intensity <- round(runif(k, 1e3, 1e6))
    cbind(mz = mz, intensity = intensity)
}
peaks <- lapply(seq_len(n_spectra), function(i) mk_peaks())

sd <- DataFrame(
    msLevel = rep(1L, n_spectra),
    rtime = rt,
    polarity = rep(1L, n_spectra),
    scanIndex = seq_len(n_spectra)
)
sd$mz <- lapply(peaks, function(p) p[, "mz"])
sd$intensity <- lapply(peaks, function(p) p[, "intensity"])

sps <- Spectra(sd, backend = MsBackendMemory())
sps$dataStorage <- rep("spectra.mzML", length(sps))

# Export to a real mzML file the workflow will read.
export(sps, backend = MsBackendMzR(), file = "spectra.mzML")

stopifnot(file.exists("spectra.mzML"), file.size("spectra.mzML") > 0)
