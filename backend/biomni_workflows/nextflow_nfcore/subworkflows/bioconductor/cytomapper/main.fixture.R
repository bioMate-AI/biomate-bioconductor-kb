suppressPackageStartupMessages({
    library(cytomapper)
    library(EBImage)
})

# Load the example datasets provided by the cytomapper package
data("pancreasImages", package = "cytomapper")
data("pancreasMasks", package = "cytomapper")

# Extract the first multi-channel image and the corresponding segmentation mask
multi_channel_img <- pancreasImages[[1]]
segmentation_mask <- pancreasMasks[[1]]

# Serialize the objects to the exact TIFF filenames expected by the workflow
writeImage(multi_channel_img, "multi_channel_images.tiff")
writeImage(segmentation_mask, "segmentation_masks.tiff")

# Guarantee the declared input files exist
stopifnot(file.exists("multi_channel_images.tiff"))
stopifnot(file.exists("segmentation_masks.tiff"))