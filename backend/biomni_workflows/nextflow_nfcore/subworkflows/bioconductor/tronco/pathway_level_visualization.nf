#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TRONCO — pathway_level_visualization
// Group genomic events into custom pathways and visualize their alteration patterns across samples.
// Input: dataset.RData
// Container: quay.io/biocontainers/bioconductor-tronco:2.42.0--r45hdfd78af_0
// R packages: TRONCO
// Bioconductor: 3.20 | R: 4.4
// Requires: TRONCO
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a custom pathway and extract its events
//  * 2. [Visualization & Output] Visualize the custom pathway using oncoprint
//  * 3. [Visualization & Output] Visualize multiple pathways simultaneously (aggregated or non-aggregated) using pathway.visualization

nextflow.enable.dsl = 2

process BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("TRONCO")
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
        
    # Load required library
    library(TRONCO)
    
    # -------------------------------------------------------------------------
    # 1. Load the input dataset
    # -------------------------------------------------------------------------
    # Read the user-provided dataset.RData file from the working directory
    if (!file.exists("dataset.RData")) {
      stop("Error: dataset.RData not found in the working directory.")
    }
    
    # Load the RData file into a temporary environment to identify the TRONCO object
    env <- new.env()
    load("dataset.RData", envir = env)
    obj_names <- ls(env)
    
    aCML <- NULL
    for (name in obj_names) {
      obj <- env[[name]]
      # Identify the TRONCO object (typically a list structure with TRONCO class or attributes)
      if (inherits(obj, "TRONCO") || (is.list(obj) && any(c("genotypes", "annotations") %in% names(obj)))) {
        aCML <- obj
        break
      }
    }
    
    # Fallback if no explicit TRONCO class is detected
    if (is.null(aCML) && length(obj_names) > 0) {
      aCML <- env[[obj_names[1]]]
    }
    
    if (is.null(aCML)) {
      stop("Error: Could not retrieve a valid TRONCO dataset from dataset.RData.")
    }
    
    # Extract available genes dynamically to avoid hardcoded names
    available_genes <- as.genes(aCML)
    if (length(available_genes) == 0) {
      stop("Error: No genes found in the dataset.")
    }
    
    # -------------------------------------------------------------------------
    # 2. Define a custom pathway and extract its events
    # -------------------------------------------------------------------------
    pathway_genes <- available_genes[1:min(3, length(available_genes))]
    pathway = as.pathway(aCML, pathway.genes = pathway_genes, pathway.name = 'MyPATHWAY', pathway.color = 'red', aggregate.pathway = FALSE)
    
    # Save the extracted pathway object
    saveRDS(pathway, file = "pathway_object.rds")
    
    # -------------------------------------------------------------------------
    # 3. Visualize the custom pathway using oncoprint
    # -------------------------------------------------------------------------
    pdf("custom_pathway_oncoprint.pdf", width = 10, height = 8)
    oncoprint(pathway, title = 'Custom pathway', font.row = 8, cellheight = 15, cellwidth = 4)
    dev.off()
    
    # -------------------------------------------------------------------------
    # 4. Visualize multiple pathways simultaneously (non-aggregated)
    # -------------------------------------------------------------------------
    p1_genes <- available_genes[1:min(2, length(available_genes))]
    if (length(available_genes) > 2) {
      p2_genes <- available_genes[3:min(4, length(available_genes))]
    } else {
      p2_genes <- p1_genes
    }
    
    pdf("pathways_non_aggregated.pdf", width = 10, height = 8)
    pathway.visualization(aCML, pathways=list(P1 = p1_genes, P2 = p2_genes), aggregate.pathways=FALSE, font.row = 8)
    dev.off()
    
    # -------------------------------------------------------------------------
    # 5. Visualize multiple pathways simultaneously (aggregated)
    # -------------------------------------------------------------------------
    pdf("pathways_aggregated.pdf", width = 10, height = 8)
    pathway.visualization(aCML, pathways=list(P1 = p1_genes, P2 = p2_genes), aggregate.pathways = TRUE, font.row = 8)
    dev.off()

    writeLines(c(
        '"BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION":',
        paste0('    TRONCO: ', as.character(packageVersion('TRONCO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_level_visualization.csv versions.yml
    """
}

workflow BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset.RData ] ]

    main:
    BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION.out.tables
    plots    = BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION.out.plots
    objects  = BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION.out.objects
    versions = BIOC_TRONCO_PATHWAY_LEVEL_VISUALIZATION.out.versions
}
