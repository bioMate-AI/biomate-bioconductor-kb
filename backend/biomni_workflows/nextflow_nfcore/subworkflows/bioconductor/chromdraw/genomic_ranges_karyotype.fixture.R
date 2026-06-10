library(GenomicRanges)
library(chromDraw)

# Create the GRanges object as shown in the vignette
exampleData <- GRanges(
    seqnames = Rle(c("ACK1"), c(4)),
    ranges = IRanges(
        start = c(0, 6700000, 0, 12400000), 
        end = c(6700000, 12400000, 0, 17000000), 
        names = c("A", "B", "CENTROMERE", "C")
    ),  
    color = c("yellow", "yellow", "", "yellow")
)

# Save the GRanges object to the expected RDS file
saveRDS(exampleData, "genomic_ranges_object")

# Create the color data.frame as shown in the vignette
name <- c("yellow", "red")
r <- c(255, 255)
g <- c(255, 0)
b <- c(0, 0)
exampleColor <- data.frame(name, r, g, b)

# Save the color data.frame to the expected CSV file
write.csv(exampleColor, "color_dataframe", row.names = FALSE, quote = FALSE)