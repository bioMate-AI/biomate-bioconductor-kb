#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goTools — custom_endnode_comparison
// Compare gene lists using a customized set of GO end nodes up to a specific rank/level.
// Input: subset
// Container: quay.io/biocontainers/bioconductor-gotools:1.84.0--r45hdfd78af_0
// R packages: GO.db, goTools
// Bioconductor: 3.20 | R: 4.4
// Requires: GO.db, goTools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Save the comparison matrix as a CSV file
//  * 2. [Input & Preparation] Save the comparison matrix as an RDS object
//  * 3. [Input & Preparation] Generate and save the comparison plot as a PDF

nextflow.enable.dsl = 2

process BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON {
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
    .bm_deps <- c("GO.db", "goTools")
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
    
    # Load required libraries
    library("goTools", verbose=FALSE)
    library("GO.db")
    
    # Read the user input file 'subset' from the working directory
    # The input is expected to be a serialized R object (RDS) containing a list of vectors of Affymetrix probe IDs
    if (file.exists("subset")) {
      subset <- readRDS("subset")
    } else if (file.exists("subset.rds")) {
      subset <- readRDS("subset.rds")
    } else {
      stop("Required input file 'subset' or 'subset.rds' not found in the working directory.")
    }
    
    # Generate a customized end node list starting from the Molecular Function root GO term up to rank 2
    MFendnode <- CustomEndNodeList("GO:0003674", rank=2)
    
    # Run ontoCompare with the custom end nodes and restrict the search to Molecular Function (MF)
    res <- ontoCompare(subset, probeType="hgu133a", endnode=MFendnode, goType="MF")
    
    # Write the meaningful results to output files
    # --- Save the comparison matrix as a CSV file ---
    write.csv(res, file="ontoCompare_results.csv", row.names=TRUE)
    
    # --- Save the comparison matrix as an RDS object ---
    saveRDS(res, file="ontoCompare_results.rds")
    
    # --- Generate and save the comparison plot as a PDF ---
    pdf("ontoCompare_plot.pdf", width=10, height=8)
    tryCatch({
      ontoPlot(res)
    }, error = function(e) {
      warning("Plotting with ontoPlot failed: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON":',
        paste0('    goTools: ', as.character(packageVersion('goTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_endnode_comparison.csv versions.yml
    """
}

workflow BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ subset ] ]

    main:
    BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON.out.tables
    plots    = BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON.out.plots
    objects  = BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON.out.objects
    versions = BIOC_GOTOOLS_CUSTOM_ENDNODE_COMPARISON.out.versions
}
