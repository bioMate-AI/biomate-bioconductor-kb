#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gep2pep — pathway_set_enrichment_analysis
// Perform Pathway-Set Enrichment Analysis (PathSEA/gene2drug) to identify conditions/drugs that consistently dysregulate a set of pathways (e.g., pathways associa
// Input: rp, gene_symbol
// Container: quay.io/biocontainers/bioconductor-gep2pep:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, gep2pep
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find pathways containing the gene of interest using gene2pathways
//  * 2. [Core Analysis] Run PathSEA on the selected pathways using PathSEA
//  * 3. [Core Analysis] Retrieve results for a specific collection using getResults
//  * 4. [Visualization & Output] Export results to XLS format using exportSEA

nextflow.enable.dsl = 2

process BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("gep2pep", "GSEABase")
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
    library(gep2pep)
    library(GSEABase)
    
    # Read user inputs from the working directory
    if (file.exists("gene_symbol")) {
      gene_symbol <- trimws(readLines("gene_symbol", warn = FALSE)[1])
    } else if (file.exists("gene_symbol.txt")) {
      gene_symbol <- trimws(readLines("gene_symbol.txt", warn = FALSE)[1])
    } else {
      stop("Required input file 'gene_symbol' or 'gene_symbol.txt' not found in the working directory.")
    }
    
    if (!dir.exists("rp")) {
      stop("Required gep2pep repository directory 'rp' not found in the working directory.")
    }
    
    # Open the gep2pep repository
    rp <- openRepository("rp")
    
    # 1. Find pathways containing the gene of interest using gene2pathways
    pathways <- gene2pathways(rp, gene_symbol)
    saveRDS(pathways, "pathways.rds")
    
    # 2. Run PathSEA on the selected pathways using PathSEA
    psea <- PathSEA(rp, pathways)
    saveRDS(psea, "psea_object.rds")
    
    # 3. Retrieve results for a specific collection using getResults
    tryCatch({
      psea_c3_TFT <- getResults(psea, "c3_TFT")
      write.csv(psea_c3_TFT, "psea_results_c3_TFT.csv", row.names = TRUE)
    }, error = function(e) {
      message("Note: 'c3_TFT' collection results could not be retrieved (perhaps not present in the input repository).")
    })
    
    # Dynamically export all available collections in the psea object to CSV
    if (!is.null(psea\$PathSEA)) {
      for (coll in names(psea\$PathSEA)) {
        tryCatch({
          res <- getResults(psea, coll)
          write.csv(res, paste0("psea_results_", coll, ".csv"), row.names = TRUE)
        }, error = function(e) {
          message("Could not export CSV results for collection: ", coll)
        })
      }
    }
    
    # 4. Export results to XLS format using exportSEA
    exportSEA(rp, psea)

    writeLines(c(
        '"BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS":',
        paste0('    gep2pep: ', as.character(packageVersion('gep2pep')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_set_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rp, gene_symbol ] ]

    main:
    BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_GEP2PEP_PATHWAY_SET_ENRICHMENT_ANALYSIS.out.versions
}
