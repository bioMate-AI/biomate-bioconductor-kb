#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DOSE — semantic_similarity_analysis
// Calculate semantic similarity between DO terms or genes.
// Input: gene_ids.txt
// Container: quay.io/biocontainers/bioconductor-dose:4.4.0--r45hdfd78af_0
// R packages: DOSE
// Bioconductor: 3.20 | R: 4.4
// Requires: DOSE
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the DOSE package
//  * 2. [Core Analysis] Compute semantic similarity using doSim, geneSim, clusterSim, or mclusterSim

nextflow.enable.dsl = 2

process BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("DOSE")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load the DOSE package
        library(DOSE)
        
        # Read the user input file
        if (!file.exists("gene_ids.txt")) {
          stop("Error: 'gene_ids.txt' not found in the working directory.")
        }
        
        ids <- readLines("gene_ids.txt")
        ids <- trimws(ids)
        ids <- ids[ids != ""]
        
        if (length(ids) == 0) {
          stop("Error: 'gene_ids.txt' is empty.")
        }
        
        # Detect whether the input contains DO term IDs or Entrez Gene IDs
        is_doid <- any(grepl("^DOID", ids, ignore.case = TRUE))
        
        # Compute semantic similarity using the appropriate DOSE function
        if (is_doid) {
          message("Detected DO term IDs. Computing semantic similarity using doSim...")
          sim_matrix <- doSim(ids, ids, measure = "Wang")
        } else {
          message("Detected Gene IDs. Computing semantic similarity using geneSim...")
          sim_matrix <- geneSim(ids, ids, measure = "Wang")\$geneSim
        }
        
        # Save the similarity matrix to a CSV file
        write.csv(sim_matrix, file = "semantic_similarity_matrix.csv", row.names = TRUE)
        
        # Save the similarity matrix as an RDS object
        saveRDS(sim_matrix, file = "semantic_similarity_matrix.rds")
        
        # Generate and save the similarity plot using heatmap
        tryCatch({
          pdf("semantic_similarity_plot.pdf", width = 8, height = 8)
          heatmap(sim_matrix)
          dev.off()
          message("Similarity plot successfully saved to 'semantic_similarity_plot.pdf'")
        }, error = function(e) {
          warning("Could not generate similarity plot: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })
        
        message("Semantic similarity analysis completed successfully.")

    writeLines(c(
        '"BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS":',
        paste0('    DOSE: ', as.character(packageVersion('DOSE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_semantic_similarity_analysis.csv versions.yml
    """
}

workflow BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_ids.txt ] ]

    main:
    BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS.out.tables
    plots    = BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS.out.plots
    objects  = BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS.out.objects
    versions = BIOC_DOSE_SEMANTIC_SIMILARITY_ANALYSIS.out.versions
}
