#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fgsea — over_representation_analysis
// Perform hypergeometric-based over-representation analysis on a list of genes of interest.
// Input: gene_list.txt, background_universe.txt, mouse.reactome.gmt
// Container: quay.io/biocontainers/bioconductor-fgsea:1.36.2--r45ha27e39d_0
// Requires: data.table, fgsea, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define foreground and background gene sets
//  * 2. [Core Analysis] Run ORA using the fora function
//  * 3. [Core Analysis] Inspect and filter enriched pathways

nextflow.enable.dsl = 2

process BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(fgsea)
        library(data.table)
        library(ggplot2)
        
        # ==========================================
        # Stage 1: Define foreground and background gene sets
        # ==========================================
        
        # Read the foreground genes of interest (e.g., top differentially expressed genes)
        if (!file.exists("gene_list.txt")) {
          stop("Error: 'gene_list.txt' not found in the working directory.")
        }
        fg <- readLines("gene_list.txt")
        fg <- unique(fg[fg != ""])
        
        # Read the background universe of genes
        if (!file.exists("background_universe.txt")) {
          stop("Error: 'background_universe.txt' not found in the working directory.")
        }
        bg <- readLines("background_universe.txt")
        bg <- unique(bg[bg != ""])
        
        # Read the Reactome pathways GMT file
        if (!file.exists("mouse.reactome.gmt")) {
          stop("Error: 'mouse.reactome.gmt' not found in the working directory.")
        }
        examplePathways <- gmtPathways("mouse.reactome.gmt")
        
        # ==========================================
        # Stage 2: Run ORA using the fora function
        # ==========================================
        
        # Perform hypergeometric-based over-representation analysis
        foraRes <- fora(genes=fg, universe=bg, pathways=examplePathways)
        
        # Inspect the results
        head(foraRes)
        
        # ==========================================
        # Stage 3: Inspect and filter enriched pathways
        # ==========================================
        
        # Order results by significance (p-value)
        foraRes <- foraRes[order(pval)]
        
        # Write the complete results table to a CSV file
        fwrite(foraRes, file="fora_results.csv", sep=",", sep2=c("", " ", ""))
        
        # Save the results as an RDS object for downstream R analyses
        saveRDS(foraRes, file="fora_results.rds")
        
        # Generate a visualization of the top 20 enriched pathways
        top_res <- head(foraRes, 20)
        
        if (nrow(top_res) > 0) {
          # Order pathways for plotting
          top_res[, pathway := factor(pathway, levels=rev(pathway))]
          
          # Create a bar plot of fold enrichment, colored by significance
          p <- ggplot(top_res, aes(x=foldEnrichment, y=pathway, fill=-log10(padj))) +
            geom_bar(stat="identity") +
            scale_fill_gradient(low="blue", high="red") +
            theme_minimal() +
            labs(
              title="Top Enriched Pathways (Over-Representation Analysis)",
              x="Fold Enrichment",
              y="Pathway",
              fill="-log10(adj. p-value)"
            ) +
            theme(
              plot.title = element_text(hjust = 0.5, face = "bold"),
              axis.text.y = element_text(size = 8)
            )
          
          # Save the plot to a PDF file
          ggsave("fora_top_pathways.pdf", plot=p, width=10, height=8)
        } else {
          warning("No pathways found to plot.")
        }

    writeLines(c(
        '"BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS":',
        paste0('    fgsea: ', as.character(packageVersion('fgsea')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_over_representation_analysis.csv versions.yml
    """
}

workflow BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_list.txt, background_universe.txt, mouse.reactome.gmt ] ]

    main:
    BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS.out.tables
    plots    = BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS.out.plots
    objects  = BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS.out.objects
    versions = BIOC_FGSEA_OVER_REPRESENTATION_ANALYSIS.out.versions
}
