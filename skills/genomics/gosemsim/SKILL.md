---
name: bioconductor-gosemsim
description: The semantic comparisons of Gene Ontology (GO) annotations provide quantitative ways to compute similarities between genes and gene groups, and have became important basis for many bioinformatics analysis approaches. GOSemSim is an R packag
when_to_use: Use when: Measuring semantic similarity among GO terms.; Computing functional similarity among gene products.; Performing GO semantic similarity analyses within stem cell transcriptional networks or other biomedical contexts.. Not for: For general biomedical knowledge mining tasks that do not involve Gene Ontology semantic similarity, refer to broader biomedical knowledge mining resources.; When performing analyses that do not require quantitative semantic comparisons of GO annotat
user-invocable: false
---

# GOSemSim

`GOSemSim` is an R package designed for semantic similarity analysis among Gene Ontology (GO) terms and gene products.

## When to Use
- Measuring semantic similarity among GO terms.
- Computing functional similarity among gene products.
- Performing GO semantic similarity analyses within stem cell transcriptional networks or other biomedical contexts.

## When NOT to Use
- For general biomedical knowledge mining tasks that do not involve Gene Ontology semantic similarity, refer to broader biomedical knowledge mining resources.
- When performing analyses that do not require quantitative semantic comparisons of GO annotations.

## Data Requirements
- Gene Ontology (GO) annotations.
- Gene and gene product datasets requiring functional similarity comparison.

## Key Parameters
- No specific R function parameters are detailed in the provided short vignette text. Please refer to the external full documentation for parameter specifications.

## Best Practices
- Refer to the comprehensive online book (https://yulab-smu.top/biomedical-knowledge-mining-book/) for the full vignette, detailed workflows, and tutorials.
- When seeking assistance, post questions to the Bioconductor support site and tag the post with `GOSemSim`.
- Cite the appropriate primary publications when using `GOSemSim` in published research.

## Common Pitfalls
- Searching for detailed code examples in the package's built-in short vignette; fix this by visiting the external online biomedical knowledge mining book for the complete documentation.
- Failing to tag support questions properly; fix this by tagging posts with `GOSemSim` on the Bioconductor support site.

## Code Example

```r
#!/usr/bin/env Rscript
    
    # Load required libraries
    library(rtracklayer)
    library(GenomicRanges)
    library(GOSemSim)
    library(org.Hs.eg.db) # Standard organism database for human annotation
    
    # Define parameters
    ONTOLOGY <- "BP"
    MEASURE <- "Wang"
    
    # -------------------------------------------------------------------------
    # Stage 1: Import and Parse Inputs
    # -------------------------------------------------------------------------
    message("Stage 1: Importing genomic regions and metadata...")
    
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import BED file using rtracklayer
    gr <- rtracklayer::import("regions.bed")
    
    # Extract gene identifiers from the 'name' column of the BED file
    if (!"name" %in% colnames(mcols(gr))) {
      stop("The BED file must contain a 'name' column representing gene identifiers.")
    }
    
    genes <- unique(mcols(gr)\$name)
    genes <- genes[!is.na(genes) & genes != ""]
    
    if (length(genes) == 0) {
      stop("No valid gene identifiers found in the 'name' column of the BED file.")
    }
    
    # Read optional metadata/coldata
    coldata <- NULL
    if (file.exists("coldata.csv")) {
      message("Found coldata.csv. Loading metadata for cluster-level analysis...")
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    }
    
    # -------------------------------------------------------------------------
    # Stage 2: Prepare GO Data
    # -------------------------------------------------------------------------
    message("Stage 2: Preparing GO database annotation...")
    
    # Determine keytype (ENTREZID if all numeric, otherwise SYMBOL)
    is_numeric_id <- all(grepl("^\\d+\$", genes))
    key_type <- if (is_numeric_id) "ENTREZID" else "SYMBOL"
    message(paste("Detected gene keytype:", key_type))
    
    # Build the semantic similarity database using GOSemSim
    sem_data <- tryCatch({
      GOSemSim::godata(
        OrgDb = "org.Hs.eg.db",
        ont = ONTOLOGY,
        keytype = key_type,
        computeIC = TRUE
      )
    }, error = function(e) {
      message("Error building GO data: ", e\$message)
      NULL
    })
    
    # -------------------------------------------------------------------------
    # Stage 3: Compute Gene Semantic Similarity
    # -------------------------------------------------------------------------
    message("Stage 3: Computing pairwise gene semantic similarity...")
    
    sim_matrix <- NULL
    if (!is.null(sem_data)) {
      # Limit to top 150 genes to avoid excessive computation times
      genes_to_sim <- if (length(genes) > 150) genes[1:150] else genes
      
      sim_matrix <- tryCatch({
        GOSemSim::mgeneSim(
          genes = genes_to_sim,
          semData = sem_data,
          measure = MEASURE,
          drop = TRUE
        )
      }, error = function(e) {
        message("Error computing gene similarity: ", e\$message)
        NULL
      })
    }
    
    # Write gene similarity matrix to CSV
    if (!is.null(sim_matrix)) {
      write.csv(as.data.frame(sim_matrix), "gene_similarity_matrix.csv", row.names = TRUE)
      message("Saved gene similarity matrix to 'gene_similarity_matrix.csv'.")
    } else {
      write.csv(data.frame(Warning = "Could not compute gene similarity"), "gene_similarity_matrix.csv", row.names = FALSE)
    }
    
    # -------------------------------------------------------------------------
    # Stage 4: Compute Cluster/Group Semantic Similarity
    # -------------------------------------------------------------------------
    message("Stage 4: Computing cluster-level semantic similarity...")
    
    cluster_sim_matrix <- NULL
    if (!is.null(sem_data) && !is.null(coldata)) {
      # Expecting coldata to have 'name' (matching BED names) and 'group' columns
      if ("name" %in% colnames(coldata) && "group" %in% colnames(coldata)) {
        coldata_sub <- coldata[coldata\$name %in% genes, ]
        gene_clusters <- split(coldata_sub\$name, coldata_sub\$group)
        
        # Filter to clusters with at least 2 genes
        gene_clusters <- gene_clusters[sapply(gene_clusters, length) >= 2]
        
        if (length(gene_clusters) >= 2) {
          cluster_sim_matrix <- tryCatch({
            GOSemSim::mclusterSim(
              gene_clusters,
              semData = sem_data,
              measure = MEASURE,
              combine = "BMA"
            )
          }, error = function(e) {
            message("Error computing cluster similarity: ", e\$message)
            NULL
          })
        } else {
          message("Insufficient clusters with >= 2 genes for cluster-level analysis.")
        }
      } else {
        message("Metadata 'coldata.csv' must contain 'name' and 'group' columns.")
      }
    }
    
    # Write cluster similarity matrix to CSV
    if (!is.null(cluster_sim_matrix)) {
      write.csv(as.data.frame(cluster_sim_matrix), "cluster_similarity_matrix.csv", row.names = TRUE)
      message("Saved cluster similarity matrix to 'cluster_similarity_matrix.csv'.")
    } else {
      write.csv(data.frame(Warning = "No cluster similarity computed"), "cluster_similarity_matrix.csv", row.names = FALSE)
    }
    
    # -------------------------------------------------------------------------
    # Stage 5: Visualization
    # -------------------------------------------------------------------------
    message("Stage 5: Generating similarity heatmap...")
    
    pdf("go_similarity_heatmap.pdf", width = 10, height = 10)
    if (!is.null(sim_matrix) && nrow(sim_matrix) > 1) {
      # Replace NA values with 0 for visualization purposes
      plot_mat <- sim_matrix
      plot_mat[is.na(plot_mat)] <- 0
      
      heatmap(
        plot_mat,
        main = paste("Gene GO Semantic Similarity (", MEASURE, ")", sep = ""),
        col = heat.colors(256),
        margins = c(10, 10)
      )
    } else {
      plot.new()
      text(0.5, 0.5, "Insufficient data or error occurred\nHeatmap could not be generated.", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS":
        GOSemSim: \$(Rscript -e 'cat(as.character(packageVersion("GOSemSim")))')
    END_VERSIONS
```

## Alternatives
- Other Bioconductor packages designed for functional annotation and enrichment analysis (though `GOSemSim` is specifically focused on semantic similarity).

## Citations
- Yu G. Gene Ontology Semantic Similarity Analysis Using GOSemSim. In: Kidder B. (eds) Stem Cell Transcriptional Networks. Methods in Molecular Biology, 2020, 2117:207-215. Humana, New York, NY.
- Yu G, Li F, Qin Y, Bo X, Wu Y and Wang S. GOSemSim: an R package for measuring semantic similarity among GO terms and gene products. Bioinformatics, 2010, 26(7):976-978.

## References
- Homepage: https://bioconductor.org/packages/gosemsim
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/GOSemSim/inst/doc/GOSemSim.html
