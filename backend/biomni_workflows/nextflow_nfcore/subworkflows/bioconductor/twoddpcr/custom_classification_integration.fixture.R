library(twoddpcr)
data("KRASdata", package = "twoddpcr")

dir.create("data/amplitudes", recursive = TRUE, showWarnings = FALSE)

for (well_name in names(KRASdata)) {
  file_name <- file.path("data/amplitudes", paste0(well_name, "_Amplitude.csv"))
  write.csv(KRASdata[[well_name]], file = file_name, row.names = FALSE, quote = FALSE)
}