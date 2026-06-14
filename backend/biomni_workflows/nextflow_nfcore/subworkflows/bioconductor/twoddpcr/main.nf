#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twoddpcr — standard_kmeans_mahalanobis
// Load raw ddPCR amplitude data, classify droplets using k-means, apply Mahalanobis distance-based rain filtering, and generate a Poisson concentration summary.
// Input: data/amplitudes
// Container: quay.io/biocontainers/bioconductor-twoddpcr:1.34.0--r45hdfd78af_0
// R packages: ggplot2, reshape2, twoddpcr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-twoddpcr:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "reshape2", "twoddpcr")
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
    
    # Load required libraries
    library(twoddpcr)
    library(ggplot2)
    
    # Create output directory if it doesn't exist
    dir.create("output", showWarnings = FALSE, recursive = TRUE)
    
    # --- Load raw amplitude data into a ddpcrPlate object ---
    # Reading from the user-specified directory containing raw droplet amplitude CSV files
    plate <- ddpcrPlate(wells="data/amplitudes")
    
    # --- Classify droplets using the k-means algorithm ---
    plate <- kmeansClassify(plate)
    
    # --- Apply Mahalanobis distance-based rain filtering with ---
    plate <- mahalanobisRain(plate, cMethod="kmeans", maxDistances=list(NN=35, NP=35, PN=35, PP=35))
    
    # --- Generate a Poisson concentration summary ---
    kmeansMahRainSummary <- plateSummary(plate, cMethod="kmeansMahRain")
    
    # Print the head of the summary to the console
    print(head(kmeansMahRainSummary))
    
    # Write the summary table to a CSV file
    write.csv(kmeansMahRainSummary, file="output/kmeans_mahalanobis_summary.csv", row.names=TRUE)
    
    # Save the classified ddpcrPlate object as an RDS file
    saveRDS(plate, file="output/classified_plate.rds")
    
    # Generate and save the droplet classification plot as a PDF
    pdf("output/droplet_plot_kmeans_mahalanobis.pdf", width=8, height=6)
    p <- dropletPlot(plate, cMethod="kmeansMahRain")
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS":',
        paste0('        twoddpcr: ', as.character(packageVersion("twoddpcr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_kmeans_mahalanobis.csv versions.yml
    """
}

workflow BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data/amplitudes ] ]

    main:
    BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS(ch_input)

    emit:
    tables   = BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS.out.tables
    plots    = BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS.out.plots
    objects  = BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS.out.objects
    versions = BIOC_TWODDPCR_STANDARD_KMEANS_MAHALANOBIS.out.versions
}
