#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mergeomics — step_by_step_mergeomics
// Run MSEA, merge overlapping pathways, perform weighted KDA, and export visualization files sequentially.
// Input: genes.txt, marker.txt, modules.txt, coexpr.info.txt, network.txt, symbols.txt
// Container: quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0
// R packages: Mergeomics
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("Mergeomics")
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
    
    # Load required library
    library(Mergeomics)
    
    # Define input files from the working directory
    genes_file <- "genes.txt"
    marker_file <- "marker.txt"
    modules_file <- "modules.txt"
    coexpr_info_file <- "coexpr.info.txt"
    network_file <- "network.txt"
    symbols_file <- "symbols.txt"
    
    # Verify all required input files exist
    required_files <- c(genes_file, marker_file, modules_file, coexpr_info_file, network_file, symbols_file)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Error: Missing required input files in the working directory:", paste(missing_files, collapse = ", ")))
    }
    
    # Create results directory if it doesn't exist
    if (!dir.exists("Results")) {
      dir.create("Results", recursive = TRUE)
    }
    
    # ==========================================
    # --- Initialize and run MSEA ---
    # ==========================================
    job.msea <- list()
    job.msea\$label <- "hdlc"
    job.msea\$folder <- "Results"
    job.msea\$genfile <- genes_file
    job.msea\$marfile <- marker_file
    job.msea\$modfile <- modules_file
    job.msea\$inffile <- coexpr_info_file
    job.msea\$nperm <- 100 ## default value is 20000 (this is recommended)
    
    job.msea <- ssea.start(job.msea)
    job.msea <- ssea.prepare(job.msea)
    job.msea <- ssea.control(job.msea)
    job.msea <- ssea.analyze(job.msea)
    job.msea <- ssea.finish(job.msea)
    
    # Save MSEA job object
    saveRDS(job.msea, file = file.path(job.msea\$folder, "job.msea.rds"))
    
    # ==========================================
    # --- Create intermediary datasets for KDA ---
    # ==========================================
    syms <- tool.read(symbols_file)
    syms <- syms[, c("HUMAN", "MOUSE")]
    names(syms) <- c("FROM", "TO")
    
    ## default and recommended rmax=0.33.
    ## min.module.count is the number of the pathways to be taken from the MSEA
    ## results to merge. If it is not specified (NULL), all the pathways having 
    ## MSEA-FDR value less than 0.25 will be considered for merging if they are 
    ## overlapping with the given ratio rmax. 
    job.kda <- ssea2kda(job.msea, rmax=0.2, symbols=syms, min.module.count=NULL) 
    
    # ==========================================
    # --- Configure and run wKDA ---
    # ==========================================
    job.kda\$netfile <- network_file
    job.kda <- kda.configure(job.kda)
    job.kda <- kda.start(job.kda)
    job.kda <- kda.prepare(job.kda)
    job.kda <- kda.analyze(job.kda)
    job.kda <- kda.finish(job.kda)
    
    # Save KDA job object
    saveRDS(job.kda, file = file.path(job.kda\$folder, "job.kda.rds"))
    
    # ==========================================
    # --- Export network files for Cytoscape visualization ---
    # ==========================================
    job.kda <- kda2cytoscape(job.kda)
    
    cat("Pipeline execution completed successfully. All outputs are saved in the 'Results' directory.\n")

    writeLines(c(
        '"BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS":',
        paste0('        mergeomics: ', as.character(packageVersion("mergeomics")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_mergeomics.csv versions.yml
    """
}

workflow BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes.txt, marker.txt, modules.txt, coexpr.info.txt, network.txt, symbols.txt ] ]

    main:
    BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS(ch_input)

    emit:
    tables   = BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS.out.tables
    plots    = BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS.out.plots
    objects  = BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS.out.objects
    versions = BIOC_MERGEOMICS_STEP_BY_STEP_MERGEOMICS.out.versions
}
