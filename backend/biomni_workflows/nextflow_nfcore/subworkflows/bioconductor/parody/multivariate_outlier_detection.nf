#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: parody — multivariate_outlier_detection
// Detect and visualize outliers in a multivariate dataset using Caroni and Prescott's generalized GESD method.
// Input: tcost
// Container: quay.io/biocontainers/bioconductor-parody:1.68.0--r45hdfd78af_0
// R packages: parody
// Bioconductor: 3.20 | R: 4.4
// Requires: parody
// Visualizations: biplot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the multivariate dataset
//  * 2. [Core Analysis] Run multivariate outlier detection using mv.calout.detect
//  * 3. [Visualization & Output] Visualize identified outliers using a colored pairs plot
//  * 4. [Visualization & Output] Perform principal component analysis (PCA) and visualize with a biplot
//  * 5. [Core Analysis] Remove identified outliers and re-run PCA to assess robustness

nextflow.enable.dsl = 2

process BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION {
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
    .bm_deps <- c("parody")
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
    library(parody)
    
    # 1. Load the multivariate dataset
    # The pipeline reads EXACTLY the 'tcost' file from the working directory.
    if (file.exists("tcost")) {
      tcost <- read.table("tcost", header = TRUE)
    } else if (file.exists("tcost.csv")) {
      tcost <- read.csv("tcost.csv", header = TRUE)
    } else {
      stop("Error: Input file 'tcost' or 'tcost.csv' not found in the working directory.")
    }
    
    # Ensure it is a data frame
    tcost <- as.data.frame(tcost)
    
    # 2. Run multivariate outlier detection using mv.calout.detect
    ostr = mv.calout.detect(tcost)
    print(ostr)
    saveRDS(ostr, file = "outlier_detection_results.rds")
    
    # 3. Visualize identified outliers using a colored pairs plot
    thecol = rep("black", nrow(tcost))
    if (length(ostr\$inds) > 0 && !any(is.na(ostr\$inds))) {
      thecol[ostr\$inds] = "red"
    }
    
    pdf("pairs_plot.pdf")
    pairs(tcost, col=thecol, pch=19)
    dev.off()
    
    # 4. Perform principal component analysis (PCA) and visualize with a biplot
    pc = prcomp(tcost)
    
    pdf("biplot_original.pdf")
    biplot(pc)
    dev.off()
    
    # 5. Remove identified outliers and re-run PCA to assess robustness
    if (length(ostr\$inds) > 0 && !any(is.na(ostr\$inds))) {
      ftcost = tcost[-ostr\$inds,]
    } else {
      ftcost = tcost
    }
    fpc = prcomp(ftcost)
    
    pdf("biplot_robust.pdf")
    biplot(fpc)
    dev.off()
    
    # Save the cleaned dataset
    write.csv(ftcost, "cleaned_tcost.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION":',
        paste0('    parody: ', as.character(packageVersion('parody')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multivariate_outlier_detection.csv versions.yml
    """
}

workflow BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tcost ] ]

    main:
    BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION.out.tables
    plots    = BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION.out.plots
    objects  = BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION.out.objects
    versions = BIOC_PARODY_MULTIVARIATE_OUTLIER_DETECTION.out.versions
}
