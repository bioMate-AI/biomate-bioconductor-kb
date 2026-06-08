---
name: bioconductor-keggrest
description: A package that provides a client interface to the Kyoto Encyclopedia of Genes and Genomes (KEGG) REST API. Only for academic use by academic users belonging to academic institutions (see <https://www.kegg.jp/kegg/rest/>). Note that KEGGREST
when_to_use: Use when: Exploring available KEGG databases and organisms using listDatabases() and keggList().; Retrieving specific KEGG entries, including amino acid (aaseq) or nucleotide (ntseq) sequences as AAStringSet or DNAStringSet objects using keggGet().; Downloading KEGG pathway maps as PNG images using keggGet() with the "image" option.; Searching for genes or compounds by keywords, chemical formulas, or exact . Not for: For commercial applications, use ReactomePA instead because the KEGG API is strictly restricted to academic use by academic institutions.; For offline or high-throughput batch queries of thousands of genes, use local annotation packages like org.Hs.e
user-invocable: false
---

# KEGGREST

## When to Use
- Exploring available KEGG databases and organisms using `listDatabases()` and `keggList()`.
- Retrieving specific KEGG entries, including amino acid (`aaseq`) or nucleotide (`ntseq`) sequences as `AAStringSet` or `DNAStringSet` objects using `keggGet()`.
- Downloading KEGG pathway maps as PNG images using `keggGet()` with the `"image"` option.
- Searching for genes or compounds by keywords, chemical formulas, or exact mass using `keggFind()`.
- Converting between KEGG identifiers and external database IDs (e.g., NCBI Gene ID) using `keggConv()`.

## When NOT to Use
- For commercial applications, use `ReactomePA` instead because the KEGG API is strictly restricted to academic use by academic institutions.
- For offline or high-throughput batch queries of thousands of genes, use local annotation packages like `org.Hs.eg.db` instead to avoid server-side limitations.
- For complex pathway network topology analyses, use `KEGGgraph` or `ROntoTools` instead.

## Data Requirements
- **Valid Identifiers**: Input queries must be valid KEGG identifiers (e.g., `"hsa:10458"`, `"path:hsa00010"`, `"cpd:C00493"`) or supported external identifiers.
- **Internet Connection**: An active internet connection is required to query the live KEGG REST API.

## Key Parameters
- **database**: The target KEGG database to query (e.g., `"pathway"`, `"organism"`, `"compound"`, `"genes"`).
- **query**: The search term, identifier, or vector of identifiers to retrieve (e.g., `"hsa:10458"`).
- **option**: Specific query options for `keggGet()` (e.g., `"aaseq"`, `"ntseq"`, `"image"`) or `keggFind()` (e.g., `"formula"`, `"exact_mass"`, `"mol_weight"`).

## Best Practices
- Verify the target organism's official KEGG code (e.g., `"hsa"` for human, `"eco"` for E. coli) using `keggList("organism")` before running queries.
- Limit `keggGet()` queries to a maximum of 10 identifiers at once, as the server restricts larger batches.
- Use `keggLink()` to find relationships across databases, such as retrieving all pathways associated with specific genes.

## Common Pitfalls
- **Truncated results from keggGet()**: Occurs when supplying more than 10 inputs to `keggGet()`; fix this by batching requests into chunks of 10 or fewer.
- **Invalid organism code**: Using common names instead of the official 3-4 letter KEGG code returns empty results; fix this by looking up the code with `keggList("organism")`.
- **Commercial use violation**: Occurs when using the package for non-academic purposes; fix this by switching to open-source databases like Reactome.

## Code Example

```r
#!/usr/bin/env Rscript
    
    # Load required libraries
    library(rtracklayer)
    library(GenomicRanges)
    library(KEGGREST)
    library(Biostrings)
    library(png)
    
    # Define parameters
    organism_code <- "hsa"
    
    # Stage 1: Import Genomic Regions and Metadata
    message("Stage 1: Importing genomic regions and metadata...")
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import BED file into a GRanges object
    gr <- rtracklayer::import("regions.bed")
    
    # Read optional coldata metadata if present
    coldata <- NULL
    if (file.exists("coldata.csv")) {
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    }
    
    # Extract gene identifiers from the 'name' column of the BED file
    # We assume these names represent NCBI Entrez Gene IDs (e.g., "10458")
    gene_ids <- unique(as.character(mcols(gr)\$name))
    gene_ids <- gene_ids[!is.na(gene_ids) & gene_ids != ""]
    
    if (length(gene_ids) == 0) {
      stop("No valid gene identifiers found in the 'name' column of regions.bed.")
    }
    
    # Stage 2: Map Identifiers to KEGG Genes
    message("Stage 2: Mapping NCBI Gene IDs to KEGG Gene IDs...")
    ncbi_query <- paste0("ncbi-geneid:", gene_ids)
    
    kegg_genes <- tryCatch({
      keggConv(organism_code, ncbi_query)
    }, error = function(e) {
      warning("keggConv failed. Attempting direct prefixing fallback: ", e\$message)
      # Fallback: construct standard KEGG gene IDs directly
      fallback_vals <- paste0(organism_code, ":", gene_ids)
      names(fallback_vals) <- ncbi_query
      fallback_vals
    })
    
    # Stage 3: Link KEGG Genes to Pathways
    message("Stage 3: Linking KEGG Genes to Pathways...")
    pathway_links <- tryCatch({
      keggLink("pathway", as.character(kegg_genes))
    }, error = function(e) {
      warning("keggLink failed: ", e\$message)
      NULL
    })
    
    # Stage 4: Build Comprehensive Mapping Table
    message("Stage 4: Building mapping table and retrieving pathway names...")
    
    # Convert GRanges to a standard data frame
    regions_df <- as.data.frame(gr)
    
    # Create a lookup table for the ID conversion
    mapping_df <- data.frame(
      name = gsub("ncbi-geneid:", "", names(kegg_genes)),
      kegg_gene_id = as.character(kegg_genes),
      stringsAsFactors = FALSE
    )
    
    # Merge genomic regions with KEGG gene IDs
    merged_df <- merge(regions_df, mapping_df, by = "name", all.x = TRUE)
    
    # Merge pathway links
    if (!is.null(pathway_links) && length(pathway_links) > 0) {
      pathway_df <- data.frame(
        kegg_gene_id = names(pathway_links),
        pathway_id = as.character(pathway_links),
        stringsAsFactors = FALSE
      )
      merged_df <- merge(merged_df, pathway_df, by = "kegg_gene_id", all.x = TRUE)
    } else {
      merged_df\$pathway_id <- NA
    }
    
    # Helper function to retrieve pathway names in chunks of 10 (KEGG API limit)
    get_pathway_names <- function(pathway_ids) {
      pathway_ids <- unique(na.omit(pathway_ids))
      if (length(pathway_ids) == 0) return(character(0))
      
      chunks <- split(pathway_ids, ceiling(seq_along(pathway_ids) / 10))
      names_list <- list()
      
      for (chunk in chunks) {
        tryCatch({
          res <- keggGet(chunk)
          for (i in seq_along(res)) {
            p_id <- chunk[i]
            p_name <- res[[i]]\$NAME
            if (!is.null(p_name)) {
              names_list[[p_id]] <- p_name
            }
          }
        }, error = function(e) {
          message("Error fetching pathway details for chunk: ", e\$message)
        })
      }
      return(unlist(names_list))
    }
    
    # Retrieve and map pathway names
    unique_pathways <- unique(na.omit(merged_df\$pathway_id))
    pathway_names <- get_pathway_names(unique_pathways)
    
    if (length(pathway_names) > 0) {
      pathway_names_df <- data.frame(
        pathway_id = names(pathway_names),
        pathway_name = as.character(pathway_names),
        stringsAsFactors = FALSE
      )
      merged_df <- merge(merged_df, pathway_names_df, by = "pathway_id", all.x = TRUE)
    } else {
      merged_df\$pathway_name <- NA
    }
    
    # Merge optional coldata if available
    if (!is.null(coldata)) {
      common_cols <- intersect(colnames(coldata), colnames(merged_df))
      if (length(common_cols) > 0) {
        merged_df <- merge(merged_df, coldata, by = common_cols, all.x = TRUE)
      }
    }
    
    # Write mapping table to CSV
    write.csv(merged_df, "kegg_mappings.csv", row.names = FALSE)
    message("Saved mapping table to 'kegg_mappings.csv'.")
    
    # Stage 5: Retrieve Gene Sequences
    message("Stage 5: Retrieving amino acid sequences...")
    unique_kegg_genes <- unique(na.omit(merged_df\$kegg_gene_id))
    # Limit to top 10 genes to respect API limits and performance
    genes_for_seq <- head(unique_kegg_genes, 10)
    
    if (length(genes_for_seq) > 0) {
      tryCatch({
        aa_seqs <- keggGet(genes_for_seq, "aaseq")
        Biostrings::writeXStringSet(aa_seqs, "gene_sequences.fasta")
        message("Saved amino acid sequences to 'gene_sequences.fasta'.")
      }, error = function(e) {
        warning("Failed to retrieve sequences: ", e\$message)
        writeLines(">no_sequences\n", "gene_sequences.fasta")
      })
    } else {
      writeLines(">no_sequences\n", "gene_sequences.fasta")
    }
    
    # Stage 6: Download Pathway Diagram
    message("Stage 6: Downloading top pathway diagram...")
    if (length(unique_pathways) > 0) {
      # Identify the most frequently occurring pathway in our dataset
      pathway_counts <- table(merged_df\$pathway_id)
      top_pathway <- names(sort(pathway_counts, decreasing = TRUE))[1]
      top_pathway_clean <- gsub("path:", "", top_pathway)
      
      tryCatch({
        png_data <- keggGet(top_pathway_clean, "image")
        png::writePNG(png_data, "top_pathway.png")
        message(sprintf("Saved top pathway diagram (%s) to 'top_pathway.png'.", top_pathway_clean))
      }, error = function(e) {
        warning("Failed to download pathway image: ", e\$message)
        writeLines("Failed to download pathway image", "top_pathway.png")
      })
    } else {
      writeLines("No pathways found to visualize", "top_pathway.png")
    }
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING":
        KEGGREST: \$(Rscript -e 'cat(as.character(packageVersion("KEGGREST")))')
    END_VERSIONS
```

## Alternatives
- `ReactomePA`: For pathway analysis using the open-source, commercially unrestricted Reactome database.
- `clusterProfiler`: For comprehensive enrichment analysis integrating KEGG and GO annotations locally.
- `AnnotationDbi`: For local, offline mapping of gene IDs without relying on web APIs.

## Citations
- Tenenbaum D (2024). KEGGREST: Client-side REST access to the Kyoto Encyclopedia of Genes and Genomes (KEGG). R package version 1.46.0.
- Kanehisa M, Goto S (2000). KEGG: kyoto encyclopedia of genes and genomes. Nucleic Acids Research, 28(1), 27-30.

## References
- Homepage: https://bioconductor.org/packages/KEGGREST
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/KEGGREST/inst/doc/KEGGREST-vignette.html
