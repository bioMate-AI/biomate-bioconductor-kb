#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPIA — spia_with_custom_kegg_data
// Parse up-to-date KGML (XML) files downloaded from KEGG to build custom pathway data and run SPIA analysis.
// Input: mydir, DE_Colorectal, ALL_Colorectal
// Container: quay.io/biocontainers/bioconductor-spia:2.62.0--r45hdfd78af_0
// R packages: SPIA
// Bioconductor: 3.20 | R: 4.4
// Requires: SPIA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse the KGML files and generate SPIA-compatible data using the makeSPIAdata function
//  * 2. [Core Analysis] Run the SPIA analysis using the spia function, pointing to the directory containing the newly generated data

nextflow.enable.dsl = 2

process BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA {
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
    .bm_deps <- c("SPIA")
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
    library(SPIA)
    
    # Define input paths in the working directory
    de_file <- "DE_Colorectal.rds"
    all_file <- "ALL_Colorectal.rds"
    mydir <- "mydir"
    
    # Validate presence of user inputs
    if (!file.exists(de_file)) {
      stop(paste("Error: Required input file missing:", de_file))
    }
    if (!file.exists(all_file)) {
      stop(paste("Error: Required input file missing:", all_file))
    }
    if (!dir.exists(mydir)) {
      stop(paste("Error: Required input directory containing KGML files is missing:", mydir))
    }
    
    # Read user inputs
    DE_Colorectal <- readRDS(de_file)
    ALL_Colorectal <- readRDS(all_file)
    
    # 1. Parse the KGML files and generate SPIA-compatible data
    makeSPIAdata(kgml.path=mydir,organism="hsa",out.path="./")
    
    # 2. Run the SPIA analysis pointing to the directory containing the newly generated data
    res<-spia(de=DE_Colorectal, all=ALL_Colorectal, organism="hsa",data.dir="./")
    
    # Write outputs
    write.csv(res, "spia_results.csv", row.names = FALSE)
    saveRDS(res, "spia_results.rds")
    
    # Generate and save the SPIA two-way evidence plot
    pdf("spia_evidence_plot.pdf", width=7, height=7)
    tryCatch({
      plotP(res, threshold=0.05)
    }, error = function(e) {
      warning("Could not generate SPIA plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA":',
        paste0('    SPIA: ', as.character(packageVersion('SPIA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spia_with_custom_kegg_data.csv versions.yml
    """
}

workflow BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mydir, DE_Colorectal, ALL_Colorectal ] ]

    main:
    BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA(ch_input)

    emit:
    tables   = BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA.out.tables
    plots    = BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA.out.plots
    objects  = BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA.out.objects
    versions = BIOC_SPIA_SPIA_WITH_CUSTOM_KEGG_DATA.out.versions
}
