#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: parody — univariate_outlier_detection
// Detect outliers in a univariate numeric vector using various parametric and resistant methods.
// Input: lead
// Container: quay.io/biocontainers/bioconductor-parody:1.68.0--r45hdfd78af_0
// R packages: BiocStyle, parody
// Bioconductor: 3.20 | R: 4.4
// Requires: parody
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and define the univariate dataset
//  * 2. [Visualization & Output] Visualize the distribution using a standard boxplot
//  * 3. [Core Analysis] Detect outliers using the boxplot method with custom scaling
//  * 4. [Core Analysis] Detect outliers using the boxplot method with ideal calibration
//  * 5. [Core Analysis] Detect outliers using the Generalized Extreme Studentized Deviate (GESD) procedure
//  * 6. [Core Analysis] Detect outliers using the median and MAD (medmad) method with Hampel scaling
//  * 7. [Core Analysis] Detect outliers using the shorth-based detector

nextflow.enable.dsl = 2

process BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION {
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
    .bm_deps <- c("BiocStyle", "parody")
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
    
    # 1. Load the package and define the univariate dataset by reading the user input file
    library(parody)
    
    if (file.exists("lead")) {
      lead <- scan("lead", quiet=TRUE)
    } else if (file.exists("lead.csv")) {
      lead <- read.csv("lead.csv", header=FALSE)[[1]]
    } else if (file.exists("lead.txt")) {
      lead <- scan("lead.txt", quiet=TRUE)
    } else {
      stop("Error: Input file 'lead' not found in the working directory.")
    }
    
    # 2. Visualize the distribution using a standard boxplot
    pdf("boxplot_lead.pdf")
    boxplot(lead)
    dev.off()
    
    # 3. Detect outliers using the boxplot method with custom scaling
    res_boxplot_custom <- calout.detect(lead, alpha=.05, method="boxplot", scaling=function(n,alpha) 1.5)
    
    # 4. Detect outliers using the boxplot method with ideal calibration
    res_boxplot_ideal <- calout.detect(lead, alpha=.05, method="boxplot", ftype="ideal")
    
    # 5. Detect outliers using the Generalized Extreme Studentized Deviate (GESD) procedure
    # Note: k must be less than half the sample size. We set k=5 as in the documented code.
    res_gesd <- calout.detect(lead, alpha=.05, method="GESD", k=5)
    
    # 6. Detect outliers using the median and MAD (medmad) method with Hampel scaling
    res_medmad <- calout.detect(lead, alpha=.05, method="medmad", scaling=hamp.scale.3)
    
    # 7. Detect outliers using the shorth-based detector
    res_shorth <- calout.detect(lead, alpha=.05, method="shorth")
    
    # Save individual results as RDS objects
    saveRDS(res_boxplot_custom, "outliers_boxplot_custom.rds")
    saveRDS(res_boxplot_ideal, "outliers_boxplot_ideal.rds")
    saveRDS(res_gesd, "outliers_gesd.rds")
    saveRDS(res_medmad, "outliers_medmad.rds")
    saveRDS(res_shorth, "outliers_shorth.rds")
    
    # Format and save a combined summary table
    format_res <- function(res) {
      inds <- paste(res\$ind, collapse=", ")
      vals <- paste(res\$val, collapse=", ")
      region <- paste(round(res\$outlier.region, 4), collapse=" to ")
      data.frame(Indices = inds, Values = vals, Outlier_Region = region, stringsAsFactors = FALSE)
    }
    
    summary_df <- rbind(
      data.frame(Method = "Boxplot Custom", format_res(res_boxplot_custom)),
      data.frame(Method = "Boxplot Ideal", format_res(res_boxplot_ideal)),
      data.frame(Method = "GESD", format_res(res_gesd)),
      data.frame(Method = "MedMad (Hampel)", format_res(res_medmad)),
      data.frame(Method = "Shorth", format_res(res_shorth))
    )
    
    write.csv(summary_df, "outliers_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION":',
        paste0('    parody: ', as.character(packageVersion('parody')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_univariate_outlier_detection.csv versions.yml
    """
}

workflow BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lead ] ]

    main:
    BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION.out.tables
    plots    = BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION.out.plots
    objects  = BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION.out.objects
    versions = BIOC_PARODY_UNIVARIATE_OUTLIER_DETECTION.out.versions
}
