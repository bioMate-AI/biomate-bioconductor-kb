library(cytomapper)
library(EBImage)

# 1. Prepare multi-channel image
data("pancreasImages", package = "cytomapper")
img <- pancreasImages[[1]]

# Normalize to [0, 1] to prevent EBImage::writeImage from clipping values > 1
img_max <- max(img)
if (img_max > 0) {
    img <- img / img_max
}
writeImage(img, "large_multi_channel_images.tiff", bits.per.sample = 16)

# 2. Prepare segmentation mask
# Prefer the exact mask files shipped in the package's extdata
mask_files <- list.files(system.file("extdata", package = "cytomapper"), pattern = "mask.tiff", full.names = TRUE)

if (length(mask_files) > 0) {
    file.copy(mask_files[1], "large_segmentation_masks.tiff", overwrite = TRUE)
} else {
    # Fallback to the pancreasMasks dataset if extdata is unavailable
    data("pancreasMasks", package = "cytomapper")
    mask <- pancreasMasks[[1]]
    
    # Divide by 65535 so that 16-bit TIFF writing (which multiplies by 65535) 
    # restores the original integer cell IDs
    mask_norm <- mask / 65535
    writeImage(mask_norm, "large_segmentation_masks.tiff", bits.per.sample = 16)
}

# Verify files were created
stopifnot(file.exists("large_multi_channel_images.tiff"))
stopifnot(file.exists("large_segmentation_masks.tiff"))