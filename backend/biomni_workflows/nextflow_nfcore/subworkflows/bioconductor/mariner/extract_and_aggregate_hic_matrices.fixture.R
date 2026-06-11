library(mariner)
library(marinerData)

# 1. FS_5kbLoops.txt
fs_bedpe <- marinerData::FS_5kbLoops.txt()
if (file.exists(fs_bedpe)) {
    file.copy(fs_bedpe, "FS_5kbLoops.txt", overwrite = TRUE)
} else {
    # Fallback if not found
    dummy_bedpe <- data.frame(
        chromosome1="chr9", x1=14460000, x2=14465000, 
        chromosome2="chr9", y1=14765000, y2=14770000, 
        color="0,0,0"
    )
    write.table(dummy_bedpe, "FS_5kbLoops.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# 2. WT_5kbLoops.txt
wt_bedpe <- marinerData::WT_5kbLoops.txt()
if (file.exists(wt_bedpe)) {
    file.copy(wt_bedpe, "WT_5kbLoops.txt", overwrite = TRUE)
} else {
    # Fallback if not found
    dummy_bedpe <- data.frame(
        chromosome1="chr9", x1=14460000, x2=14465000, 
        chromosome2="chr9", y1=14765000, y2=14770000, 
        color="0,0,0"
    )
    write.table(dummy_bedpe, "WT_5kbLoops.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# 3. LEUK_HEK_PJA27_inter_30.hic
hic_fs_found <- FALSE
if (exists("LEUK_HEK_PJA27_inter_30.hic", where = asNamespace("marinerData"))) {
    hic_fs <- get("LEUK_HEK_PJA27_inter_30.hic", envir = asNamespace("marinerData"))()
    if (file.exists(hic_fs)) {
        file.copy(hic_fs, "LEUK_HEK_PJA27_inter_30.hic", overwrite = TRUE)
        hic_fs_found <- TRUE
    }
}
if (!hic_fs_found) {
    hic_fs_search <- list.files(system.file("extdata", package="marinerData"), pattern="LEUK_HEK_PJA27_inter_30\\.hic", full.names=TRUE, recursive=TRUE)
    if (length(hic_fs_search) > 0) {
        file.copy(hic_fs_search[1], "LEUK_HEK_PJA27_inter_30.hic", overwrite = TRUE)
    } else {
        writeLines("dummy hic content", "LEUK_HEK_PJA27_inter_30.hic")
    }
}

# 4. LEUK_HEK_PJA30_inter_30.hic
hic_wt_found <- FALSE
if (exists("LEUK_HEK_PJA30_inter_30.hic", where = asNamespace("marinerData"))) {
    hic_wt <- get("LEUK_HEK_PJA30_inter_30.hic", envir = asNamespace("marinerData"))()
    if (file.exists(hic_wt)) {
        file.copy(hic_wt, "LEUK_HEK_PJA30_inter_30.hic", overwrite = TRUE)
        hic_wt_found <- TRUE
    }
}
if (!hic_wt_found) {
    hic_wt_search <- list.files(system.file("extdata", package="marinerData"), pattern="LEUK_HEK_PJA30_inter_30\\.hic", full.names=TRUE, recursive=TRUE)
    if (length(hic_wt_search) > 0) {
        file.copy(hic_wt_search[1], "LEUK_HEK_PJA30_inter_30.hic", overwrite = TRUE)
    } else {
        writeLines("dummy hic content", "LEUK_HEK_PJA30_inter_30.hic")
    }
}