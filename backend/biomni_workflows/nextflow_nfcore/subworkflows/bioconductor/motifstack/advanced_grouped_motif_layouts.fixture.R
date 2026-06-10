library(motifStack)

# Import motifs from the extdata directory as shown in the vignette
motif_files <- dir(file.path(find.package("motifStack"), "extdata"), pattern = "pcm$", full.names = TRUE)
motifs <- importMatrix(motif_files)

# Save the list of motifs to the expected input file
saveRDS(motifs, "pfm_list.rds")