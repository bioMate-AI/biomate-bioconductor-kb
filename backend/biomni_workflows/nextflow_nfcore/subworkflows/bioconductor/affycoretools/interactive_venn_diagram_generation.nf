#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affycoretools — interactive_venn_diagram_generation
// Generate an interactive Venn diagram showing overlapping significant genes between multiple comparisons.
// Input: fit2, contrast, design
// Container: quay.io/biocontainers/bioconductor-affycoretools:1.82.0--r45hdfd78af_0
// R packages: affycoretools, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: affycoretools, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the list of contrast columns to compare
//  * 2. [Input & Preparation] Create the Venn object using makeVenn
//  * 3. [Core Analysis] Generate and display the Venn diagram with captions using vennInLine

nextflow.enable.dsl = 2

process BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION {
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
    .bm_deps <- c("affycoretools", "limma")
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
    library(affycoretools)
    library(limma)
    
    # 1. Read User Inputs from the working directory
    if (!file.exists("fit2.rds") || !file.exists("contrast.rds") || !file.exists("design.rds")) {
      stop("Required input files (fit2.rds, contrast.rds, design.rds) not found in the working directory.")
    }
    
    fit2 <- readRDS("fit2.rds")
    contrast <- readRDS("contrast.rds")
    design <- readRDS("design.rds")
    
    # 2. Define the list of contrast columns to compare
    collist <- list(1:2)
    
    # 3. Create the Venn object using makeVenn
    venn <- makeVenn(fit2, contrast, design, collist = collist, adj.meth = "none")
    
    # Save the generated Venn object
    saveRDS(venn, "venn_object.rds")
    
    # 4. Generate and display the Venn diagram with captions using vennInLine
    cap <- list(paste("A Venn diagram. Note that the first sentence is bolded",
                      "and blue, whereas the rest is normal type and black. Usually",
                      "one would use a more useful caption than this one."))
    
    # Capture the inline HTML/Markdown output of vennInLine to a file
    output_file <- "venn_inline_output.html"
    con <- file(output_file, open = "wt")
    sink(con)
    tryCatch({
      vennInLine(venn, cap)
    }, finally = {
      sink()
      close(con)
    })
    
    cat("Workflow completed successfully.\n")
    cat("Outputs saved:\n")
    cat("- 'venn_object.rds' (Venn object)\n")
    cat("- 'venn_inline_output.html' (Interactive Venn diagram HTML output)\n")

    writeLines(c(
        '"BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION":',
        paste0('    affycoretools: ', as.character(packageVersion('affycoretools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_venn_diagram_generation.csv versions.yml
    """
}

workflow BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fit2, contrast, design ] ]

    main:
    BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION(ch_input)

    emit:
    tables   = BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION.out.tables
    plots    = BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION.out.plots
    objects  = BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION.out.objects
    versions = BIOC_AFFYCORETOOLS_INTERACTIVE_VENN_DIAGRAM_GENERATION.out.versions
}
