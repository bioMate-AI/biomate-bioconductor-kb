#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: katdetectr — standard_kataegis_detection
// Detect and visualize kataegis foci from standard genomic variant files (VCF or MAF) or VRanges objects.
// Input: pathToVCF, pathToMAF, syntheticData
// Container: quay.io/biocontainers/bioconductor-katdetectr:1.12.0--r45hdfd78af_0
// R packages: katdetectr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-katdetectr:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("katdetectr")
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
    library(katdetectr)
    
    # ==========================================
    # --- Import genomic variants from user input ---
    # ==========================================
    # Read the declared user input files from the working directory
    pathToVCF <- "pathToVCF"
    pathToMAF <- "pathToMAF"
    syntheticData <- readRDS("syntheticData")
    
    # ==========================================
    # --- Detect kataegis foci ---
    # ==========================================
    # Detect kataegis foci within the given VCF file
    kdVCF <- detectKataegis(genomicVariants = pathToVCF)
    
    # Detect kataegis foci within the given MAF file (aggregating multiple samples)
    kdMAF <- detectKataegis(genomicVariants = pathToMAF, aggregateRecords = TRUE)
    
    # Detect kataegis foci within the synthetic data
    kdSynthetic <- detectKataegis(genomicVariants = syntheticData)
    
    # Save the primary KatDetect objects as RDS files
    saveRDS(kdVCF, "kdVCF.rds")
    saveRDS(kdMAF, "kdMAF.rds")
    saveRDS(kdSynthetic, "kdSynthetic.rds")
    
    # ==========================================
    # --- Summarize and inspect KatDetect objects ---
    # ==========================================
    summary(kdVCF)
    print(kdVCF)
    show(kdVCF)
    kdVCF
    
    # ==========================================
    # --- Extract underlying data using getters ---
    # ==========================================
    vcf_variants <- getGenomicVariants(kdVCF)
    vcf_segments <- getSegments(kdVCF)
    vcf_foci <- getKataegisFoci(kdVCF)
    vcf_info <- getInfo(kdVCF)
    
    # Save extracted data to output files
    write.csv(as.data.frame(vcf_variants), "kdVCF_variants.csv", row.names = FALSE)
    write.csv(as.data.frame(vcf_segments), "kdVCF_segments.csv", row.names = FALSE)
    write.csv(as.data.frame(vcf_foci), "kdVCF_foci.csv", row.names = FALSE)
    saveRDS(vcf_info, "kdVCF_info.rds")
    
    # ==========================================
    # --- Visualize results using rainfallPlot ---
    # ==========================================
    pdf("rainfall_plots.pdf", width = 12, height = 8)
    
    # Standard rainfall plot
    rainfallPlot(kdVCF)
    
    # Rainfall plot with segmentation
    rainfallPlot(kdMAF, showSegmentation = TRUE)
    
    # Rainfall plot highlighting kataegis foci, segmentation, and specific sequences
    rainfallPlot(kdSynthetic, showKataegis = TRUE, showSegmentation = TRUE, showSequence = "Kataegis")
    
    dev.off()

    writeLines(c(
        '"BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION":',
        paste0('        katdetectr: ', as.character(packageVersion("katdetectr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_kataegis_detection.csv versions.yml
    """
}

workflow BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pathToVCF, pathToMAF, syntheticData ] ]

    main:
    BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION(ch_input)

    emit:
    tables   = BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION.out.tables
    plots    = BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION.out.plots
    objects  = BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION.out.objects
    versions = BIOC_KATDETECTR_STANDARD_KATAEGIS_DETECTION.out.versions
}
