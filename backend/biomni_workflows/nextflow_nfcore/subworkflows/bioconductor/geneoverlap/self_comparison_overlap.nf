#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneOverlap — self_comparison_overlap
// Perform a pairwise self-comparison of gene lists within a single gene set and visualize the results using customized heatmaps.
// Input: set1.rds, background_size
// Container: quay.io/biocontainers/bioconductor-geneoverlap:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneOverlap
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a GeneOverlapMatrix object for self-comparison using newGOM with a single gene set
//  * 2. [Visualization & Output] Visualize the upper triangular matrix using drawHeatmap
//  * 3. [Visualization & Output] Customize the heatmap colors, text colors, and plotted metrics (e.g., Jaccard index)

nextflow.enable.dsl = 2

process BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(GeneOverlap)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Inputs
    # -----------------------------------------------------------------------------
    if (!file.exists("set1.rds")) {
      stop("Error: 'set1.rds' file not found in the working directory.")
    }
    if (!file.exists("background_size")) {
      stop("Error: 'background_size' file not found in the working directory.")
    }
    
    # Read the gene set (named list of character vectors)
    set1 <- readRDS("set1.rds")
    
    # Read the background size (integer)
    bg <- tryCatch({
      val <- readRDS("background_size")
      if (is.numeric(val)) as.integer(val) else stop()
    }, error = function(e) {
      # Fallback to reading as plain text
      lines <- readLines("background_size", warn = FALSE)
      as.integer(trimws(lines[1]))
    })
    
    if (is.na(bg) || !is.numeric(bg)) {
      stop("Error: 'background_size' must resolve to a valid integer.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Perform Self-Comparison Overlap Analysis
    # -----------------------------------------------------------------------------
    # Create a GeneOverlapMatrix object for self-comparison using newGOM
    gom.self <- newGOM(set1, 
                       genome.size=bg)
    
    # -----------------------------------------------------------------------------
    # 3. Visualize and Save Heatmaps
    # -----------------------------------------------------------------------------
    
    # Heatmap 1: Default visualization
    pdf("heatmap_default.pdf", width = 8, height = 8)
    drawHeatmap(gom.self)
    dev.off()
    
    # Heatmap 2: Customized colors and text colors (Blues)
    pdf("heatmap_blues.pdf", width = 8, height = 8)
    drawHeatmap(gom.self, ncolused=5, grid.col="Blues", note.col="black")
    dev.off()
    
    # Heatmap 3: Customized metric (Jaccard index), colors, and text colors (Oranges)
    pdf("heatmap_jaccard_oranges.pdf", width = 8, height = 8)
    drawHeatmap(gom.self, what="Jaccard", ncolused=3, grid.col="Oranges", 
                note.col="black")
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 4. Export Results
    # -----------------------------------------------------------------------------
    # Save the GeneOverlapMatrix object
    saveRDS(gom.self, "gom_self_results.rds")
    
    # Extract and save the p-value matrix
    pval_matrix <- getMatrix(gom.self, name="pval")
    write.csv(pval_matrix, "p_value_matrix.csv", row.names = TRUE)
    
    # Extract and save the odds ratio matrix
    odds_ratio_matrix <- getMatrix(gom.self, name="odds.ratio")
    write.csv(odds_ratio_matrix, "odds_ratio_matrix.csv", row.names = TRUE)
    
    # Extract and save the Jaccard index matrix
    jaccard_matrix <- getMatrix(gom.self, name="Jaccard")
    write.csv(jaccard_matrix, "jaccard_matrix.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP":',
        paste0('    GeneOverlap: ', as.character(packageVersion('GeneOverlap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_self_comparison_overlap.csv versions.yml
    """
}

workflow BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ set1.rds, background_size ] ]

    main:
    BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP(ch_input)

    emit:
    tables   = BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP.out.tables
    plots    = BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP.out.plots
    objects  = BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP.out.objects
    versions = BIOC_GENEOVERLAP_SELF_COMPARISON_OVERLAP.out.versions
}
