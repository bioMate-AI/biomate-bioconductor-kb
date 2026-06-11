#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ROntoTools — primary_dis_regulation
// Perform Primary dis-regulation analysis to analyze signaling pathways based on the unexplained dis-regulation of genes and upstream signaling.
// Input: topTable.RData
// Container: quay.io/biocontainers/bioconductor-rontotools:2.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ROntoTools, graph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download and load KEGG pathway graphs using keggPathwayGraphs
//  * 2. [Core Analysis] Retrieve pathway names using keggPathwayNames
//  * 3. [Core Analysis] Filter differentially expressed genes and extract fold changes and p-values
//  * 4. [Core Analysis] Run Primary dis-regulation analysis using pDis
//  * 5. [Visualization & Output] Summarize results using Summary

nextflow.enable.dsl = 2

process BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION {
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
    
    # Load required libraries
    library(graph)
    library(ROntoTools)
    
    # 1. Download and load KEGG pathway graphs
    kpg <- keggPathwayGraphs("hsa", verbose = FALSE)
    
    # 2. Retrieve pathway names
    kpn <- keggPathwayNames("hsa")
    
    # 3. Load user input file and prepare data
    # The pipeline expects 'topTable.RData' in the working directory, which contains the 'top' data frame.
    loaded_objects <- load("topTable.RData")
    
    # Robust check to ensure 'top' object is available
    if (!"top" %in% loaded_objects) {
      for (obj in loaded_objects) {
        if (is.data.frame(get(obj))) {
          top <- get(obj)
          break
        }
      }
    }
    
    # Filter differentially expressed genes and extract fold changes and p-values
    fc <- top\$logFC[top\$adj.P.Val <= .01]
    names(fc) <- top\$entrez[top\$adj.P.Val <= .01]
    
    pv <- top\$P.Value[top\$adj.P.Val <= .01]
    names(pv) <- top\$entrez[top\$adj.P.Val <= .01]
    
    ref <- top\$entrez
    
    # 4. Run Primary dis-regulation analysis
    pDisRes <- pDis(x = fc, graphs = kpg, ref = ref, nboot = 200, verbose = FALSE)
    
    # 5. Summarize results
    sum_default <- Summary(pDisRes)
    sum_custom <- Summary(pDisRes, pathNames = kpn, totalpDis = FALSE,
                          pORA = FALSE, comb.pv = NULL, order.by = "ppDis")
    
    # Print head of summaries to console
    cat("--- Default Summary (Head) ---\n")
    print(head(sum_default))
    
    cat("\n--- Custom Summary Ordered by ppDis (Head) ---\n")
    print(head(sum_custom))
    
    # Save outputs to files
    saveRDS(pDisRes, file = "pDis_results.rds")
    write.csv(sum_default, file = "pDis_summary_default.csv", row.names = TRUE)
    write.csv(sum_custom, file = "pDis_summary_custom.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION":',
        paste0('    ROntoTools: ', as.character(packageVersion('ROntoTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_primary_dis_regulation.csv versions.yml
    """
}

workflow BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ topTable.RData ] ]

    main:
    BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION(ch_input)

    emit:
    tables   = BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION.out.tables
    plots    = BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION.out.plots
    objects  = BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION.out.objects
    versions = BIOC_RONTOTOOLS_PRIMARY_DIS_REGULATION.out.versions
}
