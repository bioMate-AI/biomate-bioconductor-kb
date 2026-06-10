suppressPackageStartupMessages({
    library(mariner)
    library(marinerData)
})

# Get the paths to the BEDPE files shipped with marinerData
fs_path <- marinerData::FS_5kbLoops.txt()
wt_path <- marinerData::WT_5kbLoops.txt()

# Copy them to the working directory as expected by the workflow
file.copy(fs_path, "FS_5kbLoops.txt", overwrite = TRUE)
file.copy(wt_path, "WT_5kbLoops.txt", overwrite = TRUE)