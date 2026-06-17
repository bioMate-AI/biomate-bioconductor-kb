#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNAnorm — standard_cnanorm_workflow
// Perform basic copy number profiling and normalization without estimating absolute ploidy or tumor content, suitable for heterogeneous or polyclonal tumors.
// Input: LS041
// Container: quay.io/biocontainers/bioconductor-cnanorm:1.56.0--r45h63f16b7_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNAnorm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert dataframe to CNAnorm object
//  * 2. [Core Analysis] Perform GC content normalization
//  * 3. [Core Analysis] Smooth the ratio signal
//  * 4. [Core Analysis] Find the representative peak closest to the median ratio
//  * 5. [Visualization & Output] Plot the peak distribution
//  * 6. [Core Analysis] Validate and segment the data
//  * 7. [Core Analysis] Perform discrete normalization
//  * 8. [Visualization & Output] Plot the normalized genome profile
//  * 9. [Visualization & Output] Export results to a table

nextflow.enable.dsl = 2

process BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("CNAnorm")
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
    library(CNAnorm)
    
    # 1. Read the user input file 'LS041' from the working directory
    # Handle multiple potential extensions or formats robustly.
    input_file <- "LS041"
    if (file.exists(input_file)) {
      LS041 <- read.table(input_file, header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("LS041.csv")) {
      LS041 <- read.csv("LS041.csv", stringsAsFactors = FALSE)
    } else if (file.exists("LS041.tsv")) {
      LS041 <- read.delim("LS041.tsv", stringsAsFactors = FALSE)
    } else if (file.exists("LS041.txt")) {
      LS041 <- read.table("LS041.txt", header = TRUE, stringsAsFactors = FALSE)
    } else {
      stop("Error: Input file 'LS041' (or LS041.csv/tsv/txt) not found in the working directory.")
    }
    
    # Set seed for reproducibility
    set.seed(31)
    
    # Convert dataframe to CNAnorm object
    CN <- dataFrame2object(LS041)
    
    # Define chromosomes to exclude
    toSkip <- c("chrY", "chrM")
    
    # 2. Perform GC content normalization
    CN <- gcNorm(CN, exclude=toSkip)
    
    # 3. Smooth the ratio signal
    CN <- addSmooth(CN, lambda=7)
    
    # 4. Find the representative peak closest to the median ratio
    CN <- peakPloidy(CN, exclude=toSkip, method='closest')
    
    # Open PDF device to save plots
    pdf("CNAnorm_plots.pdf", width = 10, height = 7)
    
    # 5. Plot the peak distribution
    plotPeaks(CN)
    
    # 6. Validate and segment the data
    CN <- validation(CN)
    CN <- addDNACopy(CN)
    
    # 7. Perform discrete normalization
    CN <- discreteNorm(CN)
    
    # Run the workflow function for comparison/validation as in the documented code
    set.seed(31)
    CNauto <- CNAnormWorkflow(LS041, gc.do=TRUE, gc.exclude=toSkip, peak.exclude=toSkip)
    message("Is step-by-step identical to workflow? ", identical(CN, CNauto))
    
    # 8. Plot the normalized genome profile
    plotGenome(CN, superimpose='DNACopy', show.centromeres=FALSE)
    
    # Plot subset of chromosomes
    toPlot <- c('chr10', 'chr11', 'chr12')
    subSet <- chrs(CN) %in% toPlot
    plotGenome(CN[subSet], superimpose='DNACopy')
    
    # Close PDF device
    dev.off()
    
    # 9. Export results to a table
    exportTable(CN, file = "CNAnorm_table.tab", show = 'center')
    
    # Save the final CNAnorm object as RDS
    saveRDS(CN, file = "CNAnorm_object.rds")

    writeLines(c(
        '"BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW":',
        paste0('    CNAnorm: ', as.character(packageVersion('CNAnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_cnanorm_workflow.csv versions.yml
    """
}

workflow BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ LS041 ] ]

    main:
    BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW.out.tables
    plots    = BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW.out.plots
    objects  = BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW.out.objects
    versions = BIOC_CNANORM_STANDARD_CNANORM_WORKFLOW.out.versions
}
