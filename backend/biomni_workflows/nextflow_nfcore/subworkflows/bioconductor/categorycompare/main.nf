#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: categoryCompare — compare_gene_lists_by_annotation
// Compare functional annotations (GO/KEGG) across multiple gene lists to identify shared and unique biological themes.
// Input: gene_lists.RData
// Container: quay.io/biocontainers/bioconductor-categorycompare:1.54.0--r45hdfd78af_0
// R packages: GO.db, affy, categoryCompare, estrogen, genefilter, KEGGREST, limma, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: GO.db, categoryCompare, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define gene lists, background universe, and annotation package
//  * 2. [Input & Preparation] Create a ccGeneList object specifying annotation types
//  * 3. [Core Analysis] Perform enrichment analysis using ccEnrich
//  * 4. [Core Analysis] Adjust significance cutoffs if necessary using pvalueCutoff
//  * 5. [Input & Preparation] Define comparison options using ccOptions
//  * 6. [Core Analysis] Perform comparative analysis using ccCompare
//  * 7. [Visualization & Output] Filter low-weight edges using breakEdges and export to Cytoscape using ccOutCyt

nextflow.enable.dsl = 2

process BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("GO.db", "affy", "categoryCompare", "estrogen", "genefilter", "KEGGREST", "limma", "org.Hs.eg.db")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(categoryCompare)
    library(GO.db)
    library(KEGGREST)
    library(org.Hs.eg.db)
    
    # 1. Load User Input
    if (!file.exists("gene_lists.RData")) {
      stop("Required input file 'gene_lists.RData' not found in the working directory.")
    }
    
    env <- new.env()
    load("gene_lists.RData", envir = env)
    var_names <- ls(env)
    
    if (length(var_names) < 2) {
      stop("Loaded RData must contain a universe and at least one gene list.")
    }
    
    # Identify universe dynamically (by name or fallback to the largest object)
    is_univ <- grepl("universe", var_names, ignore.case = TRUE)
    if (any(is_univ)) {
      univ_name <- var_names[is_univ][1]
    } else {
      lens <- sapply(var_names, function(x) {
        obj <- env[[x]]
        if (is.data.frame(obj)) nrow(obj) else length(obj)
      })
      univ_name <- var_names[which.max(lens)]
    }
    
    gUniv_obj <- env[[univ_name]]
    if (is.data.frame(gUniv_obj)) {
      if ("Entrez" %in% colnames(gUniv_obj)) {
        gUniverse <- as.character(gUniv_obj\$Entrez)
      } else {
        gUniverse <- as.character(gUniv_obj[[1]])
      }
    } else {
      gUniverse <- as.character(gUniv_obj)
    }
    gUniverse <- unique(gUniverse)
    
    list_names <- setdiff(var_names, univ_name)
    
    # 2. Define gene lists, background universe, and annotation package dynamically
    geneLists_list <- list()
    for (ln in list_names) {
      obj <- env[[ln]]
      if (is.data.frame(obj)) {
        if ("adj.P.Val" %in% colnames(obj) && "Entrez" %in% colnames(obj)) {
          genes <- unique(as.character(obj\$Entrez[obj\$adj.P.Val < 0.05]))
        } else if ("Entrez" %in% colnames(obj)) {
          genes <- unique(as.character(obj\$Entrez))
        } else {
          genes <- unique(as.character(obj[[1]]))
        }
      } else {
        genes <- unique(as.character(obj))
      }
      geneLists_list[[ln]] <- list(genes = genes, universe = gUniverse, annotation = 'org.Hs.eg.db')
    }
    
    # 3. Create a ccGeneList object specifying annotation types
    geneLists <- new("ccGeneList", geneLists_list, ccType=c("BP","KEGG"))
    fdr(geneLists) <- 0
    
    # 4. Perform enrichment analysis using ccEnrich
    enrichLists <- ccEnrich(geneLists)
    
    # 5. Adjust significance cutoffs if necessary using pvalueCutoff
    pvalueCutoff(enrichLists\$BP) <- 0.001
    
    # 6. Define comparison options using ccOptions
    ccOpts <- new("ccOptions", listNames=names(geneLists), outType='none')
    
    # 7. Perform comparative analysis using ccCompare
    ccResults <- ccCompare(enrichLists,ccOpts)
    
    # 8. Filter low-weight edges using breakEdges and export to Cytoscape using ccOutCyt
    ccBP <- breakEdges(ccResults\$BP, 0.2)
    
    # Wrap Cytoscape-dependent steps in tryCatch to ensure robustness in non-interactive environments
    tryCatch({
      cw.BP <- ccOutCyt(ccBP, ccOpts)
      breakEdges(cw.BP,0.4)
      breakEdges(cw.BP,0.6)
      breakEdges(cw.BP,0.8)
    }, error = function(e) {
      message("Cytoscape connection not available. Skipping cw.BP visualization steps.")
    })
    
    # 9. Hierarchical layout comparison
    graphType(enrichLists\$BP) <- "hierarchical"
    ccResultsBPHier <- ccCompare(enrichLists\$BP, ccOpts)
    
    tryCatch({
      cw.BP2 <- ccOutCyt(ccResultsBPHier, ccOpts, "BPHier")
    }, error = function(e) {
      message("Cytoscape connection not available. Skipping cw.BP2 visualization steps.")
    })
    
    tryCatch({
      cw.KEGG <- ccOutCyt(ccResults\$KEGG,ccOpts)
    }, error = function(e) {
      message("Cytoscape connection not available. Skipping cw.KEGG visualization steps.")
    })
    
    # 10. Save meaningful results to files
    saveRDS(enrichLists, "enrichLists.rds")
    saveRDS(ccResults, "ccResults.rds")
    saveRDS(ccResultsBPHier, "ccResultsBPHier.rds")
    
    # Export tables to CSV
    tryCatch({
      bp_table <- ccResults\$BP@mainTable
      write.csv(bp_table, "ccResults_BP_table.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not export BP table: ", e\$message)
    })
    
    tryCatch({
      kegg_table <- ccResults\$KEGG@mainTable
      write.csv(kegg_table, "ccResults_KEGG_table.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not export KEGG table: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION":',
        paste0('    categoryCompare: ', as.character(packageVersion('categoryCompare')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_gene_lists_by_annotation.csv versions.yml
    """
}

workflow BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_lists.RData ] ]

    main:
    BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION.out.tables
    plots    = BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION.out.plots
    objects  = BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION.out.objects
    versions = BIOC_CATEGORYCOMPARE_COMPARE_GENE_LISTS_BY_ANNOTATION.out.versions
}
