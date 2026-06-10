#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bumphunter — region_finding_from_precomputed_coefficients
// Find and package genomic regions (bumps) from precomputed coefficients or test statistics without fitting a new statistical model.
// Input: chr, pos, beta1
// Container: quay.io/biocontainers/bioconductor-bumphunter:1.52.0--r45hdfd78af_0
// R packages: bumphunter, doParallel
// Bioconductor: 3.20 | R: 4.4
// Requires: bumphunter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Group genomic locations into clusters using clusterMaker
//  * 2. [Core Analysis] Identify positive/negative segments using getSegments
//  * 3. [Core Analysis] Find and tabulate regions using regionFinder

nextflow.enable.dsl = 2

process BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("bumphunter", "doParallel")
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
    library(bumphunter)
    
    # Helper function to read user inputs robustly
    read_input_vector <- function(base_name, type = "character") {
      files_to_try <- c(
        base_name, 
        paste0(base_name, ".rds"), 
        paste0(base_name, ".csv"), 
        paste0(base_name, ".txt")
      )
      
      for (f in files_to_try) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f)) {
            val <- readRDS(f)
            return(as.vector(val))
          } else if (grepl("\\\\.csv\$", f)) {
            val <- read.csv(f, header = FALSE, stringsAsFactors = FALSE)
            if (ncol(val) == 1) {
              return(as.vector(val[[1]]))
            } else {
              return(as.vector(t(val)))
            }
          } else {
            # txt or extensionless
            if (type == "numeric") {
              return(scan(f, what = numeric(), quiet = TRUE))
            } else if (type == "integer") {
              return(scan(f, what = integer(), quiet = TRUE))
            } else {
              return(readLines(f, warn = FALSE))
            }
          }
        }
      }
      stop(paste("Required input file not found for:", base_name))
    }
    
    # Read user inputs
    chr <- as.character(read_input_vector("chr", "character"))
    pos <- as.integer(read_input_vector("pos", "integer"))
    beta1 <- as.numeric(read_input_vector("beta1", "numeric"))
    
    # Validate inputs
    if (length(chr) != length(pos) || length(pos) != length(beta1)) {
      stop("Input vectors 'chr', 'pos', and 'beta1' must have the same length.")
    }
    
    # Stage 1: Group genomic locations into clusters using clusterMaker
    cl <- clusterMaker(chr, pos, maxGap = 300)
    table(cl)
    
    # Stage 2: Identify positive/negative segments using getSegments
    segs <- getSegments(beta1, cl, cutoff=0.05)
    
    # Stage 3: Find and tabulate regions using regionFinder
    tab <- regionFinder(beta1, chr, pos, cl, cutoff=0.05)
    
    # Save outputs
    # 1. Save the regions table
    write.csv(tab, "regions.csv", row.names = FALSE)
    saveRDS(tab, "regions.rds")
    
    # 2. Save the segments list
    saveRDS(segs, "segments.rds")
    
    # 3. Generate and save diagnostic plots
    pdf("bumphunter_results.pdf", width = 10, height = 5)
    if (!is.null(segs\$upIndex) && length(segs\$upIndex) > 0) {
      num_plots <- min(4, length(segs\$upIndex))
      par(mfrow = c(1, num_plots))
      for (i in seq_len(num_plots)) {
        ind <- segs\$upIndex[[i]]
        index <- which(cl == cl[ind[1]])
        plot(pos[index], beta1[index],
             xlab = paste("position on", chr[ind[1]]),
             ylab = "beta1",
             main = paste("Segment", i))
        points(pos[ind], beta1[ind], pch = 16, col = 2)
        abline(h = 0.05, col = "blue")
      }
    } else {
      plot(pos, beta1, col = as.factor(chr), xlab = "Genomic Position", ylab = "Beta1",
           main = "Beta1 across positions (No up-segments found)")
    }
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to 'regions.csv', 'regions.rds', 'segments.rds', and 'bumphunter_results.pdf'.\n")

    writeLines(c(
        '"BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS":',
        paste0('    bumphunter: ', as.character(packageVersion('bumphunter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_region_finding_from_precomputed_coefficients.csv versions.yml
    """
}

workflow BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr, pos, beta1 ] ]

    main:
    BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS(ch_input)

    emit:
    tables   = BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS.out.tables
    plots    = BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS.out.plots
    objects  = BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS.out.objects
    versions = BIOC_BUMPHUNTER_REGION_FINDING_FROM_PRECOMPUTED_COEFFICIENTS.out.versions
}
