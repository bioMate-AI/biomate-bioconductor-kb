library(mariner)
library(marinerData)

# WT_5kbLoops.txt
wt_file <- marinerData::WT_5kbLoops.txt()
file.copy(wt_file, "WT_5kbLoops.txt", overwrite = TRUE)

# LEUK_HEK_PJA27_inter_30.hic
hic1 <- tryCatch(marinerData::LEUK_HEK_PJA27_inter_30.hic(), error = function(e) NULL)
if (!is.null(hic1) && file.exists(hic1)) {
    file.copy(hic1, "LEUK_HEK_PJA27_inter_30.hic", overwrite = TRUE)
} else {
    # Fallback to creating a dummy file if not found
    writeBin(as.raw(1:10), "LEUK_HEK_PJA27_inter_30.hic")
}

# LEUK_HEK_PJA30_inter_30.hic
hic2 <- tryCatch(marinerData::LEUK_HEK_PJA30_inter_30.hic(), error = function(e) NULL)
if (!is.null(hic2) && file.exists(hic2)) {
    file.copy(hic2, "LEUK_HEK_PJA30_inter_30.hic", overwrite = TRUE)
} else {
    # Fallback to creating a dummy file if not found
    writeBin(as.raw(1:10), "LEUK_HEK_PJA30_inter_30.hic")
}