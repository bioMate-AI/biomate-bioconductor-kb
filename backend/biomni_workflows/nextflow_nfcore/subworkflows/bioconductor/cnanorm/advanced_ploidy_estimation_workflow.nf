#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNAnorm — advanced_ploidy_estimation_workflow
// Estimate absolute ploidy and tumor content for monoclonal tumors, perform advanced segmentation, and optionally manually correct ploidy states.
// Input: LS041, hg19_hs_ideogr
// Container: quay.io/biocontainers/bioconductor-cnanorm:1.56.0--r45h63f16b7_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNAnorm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert dataframe to CNAnorm object and perform GC normalization and smoothing
//  * 2. [Core Analysis] Estimate absolute ploidy and tumor content using density method
//  * 3. [Visualization & Output] Plot peaks to inspect integer state assignments
//  * 4. [Core Analysis] Validate and perform advanced segmentation with Poisson weights and independent chromosome arms
//  * 5. [Visualization & Output] Perform discrete normalization and plot the genome
//  * 6. [Core Analysis] Manually shift the suggested ploidy state
//  * 7. [Visualization & Output] Re-normalize and plot the manually corrected genome profile

nextflow.enable.dsl = 2

process BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW {
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
    library(CNAnorm)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read LS041 dataframe
    if (file.exists("LS041.rds")) {
      LS041 <- readRDS("LS041.rds")
    } else if (file.exists("LS041.csv")) {
      LS041 <- read.csv("LS041.csv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("LS041.tsv")) {
      LS041 <- read.delim("LS041.tsv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("LS041.txt")) {
      LS041 <- read.table("LS041.txt", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("LS041")) {
      LS041 <- tryCatch({
        read.table("LS041", header = TRUE, stringsAsFactors = FALSE)
      }, error = function(e) {
        readRDS("LS041")
      })
    } else {
      stop("Required input file 'LS041' not found in the working directory.")
    }
    
    # Read hg19_hs_ideogr dataframe
    if (file.exists("hg19_hs_ideogr.rds")) {
      hg19_hs_ideogr <- readRDS("hg19_hs_ideogr.rds")
    } else if (file.exists("hg19_hs_ideogr.csv")) {
      hg19_hs_ideogr <- read.csv("hg19_hs_ideogr.csv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("hg19_hs_ideogr.tsv")) {
      hg19_hs_ideogr <- read.delim("hg19_hs_ideogr.tsv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("hg19_hs_ideogr.txt")) {
      hg19_hs_ideogr <- read.table("hg19_hs_ideogr.txt", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("hg19_hs_ideogr")) {
      hg19_hs_ideogr <- tryCatch({
        read.table("hg19_hs_ideogr", header = TRUE, stringsAsFactors = FALSE)
      }, error = function(e) {
        readRDS("hg19_hs_ideogr")
      })
    } else {
      stop("Required input file 'hg19_hs_ideogr' not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Execute CNAnorm Advanced Ploidy Estimation Workflow
    # -----------------------------------------------------------------------------
    
    set.seed(31)
    
    # Convert dataframe to CNAnorm object
    CN <- dataFrame2object(LS041)
    
    # GC normalization and smoothing
    toSkip <- c("chrY", "chrM")
    CN <- gcNorm(CN, exclude = toSkip)
    CN <- addSmooth(CN, lambda = 7)
    
    # Estimate absolute ploidy and tumor content using density method
    CN <- peakPloidy(CN, exclude = toSkip, method = 'density')
    
    # Plot peaks to inspect integer state assignments
    pdf("peaks_initial.pdf", width = 8, height = 6)
    plotPeaks(CN)
    dev.off()
    
    # Validate and perform advanced segmentation with Poisson weights and independent arms
    CN <- validation(CN)
    CN <- addDNACopy(CN, DNAcopy.weight = 'poisson', DNAcopy.segment = list(alpha = 0.001), independent.arms = TRUE, ideograms = hg19_hs_ideogr)
    CN <- discreteNorm(CN)
    
    # Plot the genome with initial segmentation
    pdf("genome_initial.pdf", width = 12, height = 6)
    plotGenome(CN, superimpose = 'DNACopy')
    dev.off()
    
    # Manually shift the suggested ploidy state
    CN <- validation(CN, ploidy = (sugg.ploidy(CN) - 1))
    
    # Plot peaks with validated states
    pdf("peaks_validated.pdf", width = 8, height = 6)
    plotPeaks(CN, show = 'validated')
    dev.off()
    
    # Re-normalize and plot the manually corrected genome profile
    CN <- discreteNorm(CN)
    
    pdf("genome_final.pdf", width = 12, height = 6)
    plotGenome(CN, superimpose = 'DNACopy')
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 3. Export Results
    # -----------------------------------------------------------------------------
    
    # Export final table
    exportTable(CN, file = "CNAnorm_table_final.tab", show = 'center')
    
    # Save final CNAnorm object
    saveRDS(CN, file = "CNAnorm_final_object.rds")

    writeLines(c(
        '"BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW":',
        paste0('    CNAnorm: ', as.character(packageVersion('CNAnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_advanced_ploidy_estimation_workflow.csv versions.yml
    """
}

workflow BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ LS041, hg19_hs_ideogr ] ]

    main:
    BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW.out.tables
    plots    = BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW.out.plots
    objects  = BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW.out.objects
    versions = BIOC_CNANORM_ADVANCED_PLOIDY_ESTIMATION_WORKFLOW.out.versions
}
