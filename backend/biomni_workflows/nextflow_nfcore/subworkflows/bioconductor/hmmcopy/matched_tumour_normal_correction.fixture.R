library(HMMcopy)

rfile <- system.file("extdata", "normal.wig", package = "HMMcopy")
gfile <- system.file("extdata", "gc.wig", package = "HMMcopy")
mfile <- system.file("extdata", "map.wig", package = "HMMcopy")
tfile <- system.file("extdata", "tumour.wig", package = "HMMcopy")

if (file.exists(rfile)) file.copy(rfile, "normal.wig", overwrite = TRUE)
if (file.exists(gfile)) file.copy(gfile, "gc.wig", overwrite = TRUE)
if (file.exists(mfile)) file.copy(mfile, "map.wig", overwrite = TRUE)
if (file.exists(tfile)) file.copy(tfile, "tumour.wig", overwrite = TRUE)