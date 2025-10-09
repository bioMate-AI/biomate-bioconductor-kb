#!/usr/bin/env Rscript

# Load required libraries
suppressPackageStartupMessages({
    library(optparse)
    library(DESeq2)
})

# Parse command line arguments
option_list <- list(
    make_option(c("--input"), type="character", 
                help="Input count matrix file"),
    make_option(c("--output"), type="character", 
                help="Output results file"),
    make_option(c("--pvalue"), type="numeric", default=0.05,
                help="P-value threshold [default %default]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Read input data
count_data <- read.table(opt$input, header=TRUE, row.names=1, sep="\t")

# Create sample metadata (simplified example)
sample_names <- colnames(count_data)
condition <- rep(c("control", "treatment"), length.out=length(sample_names))
coldata <- data.frame(condition=factor(condition), row.names=sample_names)

# Create DESeq2 object
dds <- DESeqDataSetFromMatrix(countData = count_data,
                              colData = coldata,
                              design = ~ condition)

# Run DESeq2 analysis
dds <- DESeq(dds)
res <- results(dds, alpha=opt$pvalue)

# Convert to data frame and add gene names
res_df <- data.frame(res)
res_df$gene <- rownames(res_df)

# Reorder columns
res_df <- res_df[, c("gene", "baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj")]

# Filter by adjusted p-value
res_filtered <- res_df[which(res_df$padj < opt$pvalue), ]

# Write results
write.table(res_filtered, file=opt$output, sep="\t", quote=FALSE, row.names=FALSE)

cat("Analysis complete. Found", nrow(res_filtered), "significant genes.\n")