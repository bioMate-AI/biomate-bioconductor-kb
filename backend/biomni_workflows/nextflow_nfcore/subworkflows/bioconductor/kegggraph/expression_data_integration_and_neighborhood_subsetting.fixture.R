library(KEGGgraph)
library(hgu133plus2.db)

# Load data as demonstrated in the vignette
if(requireNamespace("SPIA", quietly=TRUE)) {
  data(colorectalcancer, package="SPIA")
} else {
  load(system.file("extdata/colorectalcancerSPIA.RData", package="KEGGgraph"))
}

# Process data to create the required objects
x <- hgu133plus2ENTREZID
top$ENTREZ <- unlist(as.list(x[top$ID]))
top <- top[!is.na(top$ENTREZ),]
top <- top[!duplicated(top$ENTREZ),]
tg1 <- top[top$adj.P.Val < 0.05,]

DE_Colorectal <- tg1$logFC
names(DE_Colorectal) <- as.vector(tg1$ENTREZ)
ALL_Colorectal <- top$ENTREZ

# Serialize the objects to the expected input files
saveRDS(DE_Colorectal, "DE_Colorectal")
saveRDS(ALL_Colorectal, "ALL_Colorectal")

# Copy the required KGML file from the package's extdata
colFile <- system.file("extdata/hsa05210.xml", package="KEGGgraph")
if (file.exists(colFile)) {
  file.copy(colFile, "hsa05210.xml", overwrite = TRUE)
} else {
  # Fallback to ensure the file exists if missing from the installation
  writeLines('<?xml version="1.0"?>\n<pathway name="path:hsa05210" org="hsa" number="05210" title="Colorectal cancer"></pathway>', "hsa05210.xml")
}