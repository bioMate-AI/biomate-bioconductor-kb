#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multiGSEA — multi_omics_gsea_enrichment
// Run a multi-omics GSEA-based pathway enrichment analysis across transcriptome, proteome, and metabolome layers and aggregate the p-values.
// Input: transcriptome, proteome, metabolome
// Container: quay.io/biocontainers/bioconductor-multigsea:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: magrittr, multiGSEA, org.Hs.eg.db
// Visualizations: bar plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the multi-omics data structure using initOmicsDataStructure
//  * 2. [Core Analysis] Rank features for each omics layer using rankFeatures and assign feature names
//  * 3. [Input & Preparation] Download and map pathway definitions using getMultiOmicsFeatures
//  * 4. [Core Analysis] Calculate enrichment scores for all layers using multiGSEA
//  * 5. [Core Analysis] Extract p-values using extractPvalues and aggregate them using combinePvalues
//  * 6. [Core Analysis] Adjust combined p-values using p.adjust

nextflow.enable.dsl = 2

process BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("org.Hs.eg.db", "multiGSEA", "magrittr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    
    # Load required libraries
    library(org.Hs.eg.db)
    library(multiGSEA)
    library(magrittr)
    
    # Helper function to read input files from the working directory
    read_input_file <- function(base_name) {
      csv_file <- paste0(base_name, ".csv")
      tsv_file <- paste0(base_name, ".tsv")
      if (file.exists(csv_file)) {
        return(read.csv(csv_file, stringsAsFactors = FALSE))
      } else if (file.exists(tsv_file)) {
        return(read.delim(tsv_file, stringsAsFactors = FALSE))
      } else {
        stop(paste("Error: Could not find", csv_file, "or", tsv_file, "in the working directory."))
      }
    }
    
    # Read user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    transcriptome <- read_input_file("transcriptome")
    proteome <- read_input_file("proteome")
    metabolome <- read_input_file("metabolome")
    
    # 1. Initialize the multi-omics data structure
    omics_data <- initOmicsDataStructure(layer = c(
      "transcriptome",
      "proteome",
      "metabolome"
    ))
    
    # 2. Rank features for each omics layer and assign feature names
    omics_data\$transcriptome <- rankFeatures(
      transcriptome\$logFC,
      transcriptome\$pValue
    )
    names(omics_data\$transcriptome) <- transcriptome\$Symbol
    
    omics_data\$proteome <- rankFeatures(proteome\$logFC, proteome\$pValue)
    names(omics_data\$proteome) <- proteome\$Symbol
    
    omics_data\$metabolome <- rankFeatures(metabolome\$logFC, metabolome\$pValue)
    names(omics_data\$metabolome) <- metabolome\$HMDB
    names(omics_data\$metabolome) <- gsub(
      "HMDB", "HMDB00",
      names(omics_data\$metabolome)
    )
    
    # 3. Download and map pathway definitions
    databases <- c("kegg", "reactome")
    layers <- names(omics_data)
    
    pathways <- getMultiOmicsFeatures(
      dbs = databases, layer = layers,
      returnTranscriptome = "SYMBOL",
      returnProteome = "SYMBOL",
      returnMetabolome = "HMDB",
      useLocal = FALSE
    )
    
    # 4. Calculate enrichment scores for all layers
    enrichment_scores <- multiGSEA(pathways, omics_data)
    
    # 5. Extract p-values and aggregate them
    df <- extractPvalues(
      enrichmentScores = enrichment_scores,
      pathwayNames = names(pathways[[1]])
    )
    
    df\$combined_pval <- combinePvalues(df)
    
    # 6. Adjust combined p-values
    df\$combined_padj <- p.adjust(df\$combined_pval, method = "BH")
    
    df <- cbind(data.frame(pathway = names(pathways[[1]])), df)
    
    # Write output files
    write.csv(df, "multiGSEA_enrichment_results.csv", row.names = FALSE)
    saveRDS(enrichment_scores, "enrichment_scores.rds")
    saveRDS(pathways, "pathways.rds")
    
    # Generate a PDF plot of the top 15 pathways based on combined adjusted p-value
    tryCatch({
      pdf("top_pathways_enrichment.pdf", width = 10, height = 8)
      plot_df <- df[order(df\$combined_padj, na.last = TRUE), ]
      plot_df <- head(plot_df, 15)
      
      if (nrow(plot_df) > 0) {
        pvals <- plot_df\$combined_padj
        pvals[pvals == 0] <- min(pvals[pvals > 0], 1e-10) / 10
        y_vals <- -log10(pvals)
        
        par(mar = c(5, 20, 4, 2))
        barplot(rev(y_vals), 
                names.arg = rev(plot_df\$pathway), 
                horiz = TRUE, 
                las = 1, 
                col = "skyblue",
                xlab = "-log10(Combined Adjusted P-value)",
                main = "Top 15 Enriched Pathways (multiGSEA)")
        abline(v = -log10(0.05), col = "red", lty = 2)
      }
      dev.off()
    }, error = function(e) {
      message("Could not generate PDF plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT":',
        paste0('    multiGSEA: ', as.character(packageVersion('multiGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omics_gsea_enrichment.csv versions.yml
    """
}

workflow BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transcriptome, proteome, metabolome ] ]

    main:
    BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.tables
    plots    = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.plots
    objects  = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.objects
    versions = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.versions
}
