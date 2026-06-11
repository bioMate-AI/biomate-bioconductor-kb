#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epimutacions — case_control_epimutation_analysis
// Preprocess raw DNA methylation data, identify epimutations by comparing case samples against a reference panel, annotate the identified regions, and visualize t
// Input: baseDir, reference_panel, methy
// Container: quay.io/biocontainers/bioconductor-epimutacions:1.14.0--r45ha27e39d_0
// R packages: epimutacions, ExperimentHub, kableExtra, minfi
// Bioconductor: 3.20 | R: 4.4
// Requires: epimutacions, minfi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess raw IDAT files against a reference panel using epi_preprocess
//  * 2. [Core Analysis] Separate case and control samples
//  * 3. [Core Analysis] Run epimutation detection using epimutations
//  * 4. [Core Analysis] Annotate identified epimutations using annotate_epimutations
//  * 5. [Visualization & Output] Visualize epimutations along the genome using plot_epimutations

nextflow.enable.dsl = 2

process BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS {
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
    .bm_deps <- c("epimutacions", "ExperimentHub", "kableExtra", "minfi")
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
    library(epimutacions)
    library(minfi)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    # baseDir: directory containing raw case IDAT files and SampleSheet.csv
    baseDir <- "baseDir"
    
    # reference_panel: RGChannelSet object containing reference/control samples
    # Read from a serialized RDS file in the working directory
    reference_panel <- readRDS("reference_panel.rds")
    
    # methy: GenomicRatioSet containing preprocessed case and control samples
    # Read from a serialized RDS file in the working directory
    methy <- readRDS("methy.rds")
    
    # ==========================================
    # 2. Preprocess Raw DNA Methylation Data
    # ==========================================
    # Customize preprocessing parameters
    parameters <- norm_parameters(illumina = list("bg.correct" = FALSE))
    
    # Preprocess raw IDAT files against the reference panel
    GRset <- epi_preprocess(baseDir, reference_panel, pattern = "SampleSheet.csv")
    
    # Save preprocessed GenomicRatioSet
    saveRDS(GRset, "GRset_preprocessed.rds")
    
    # ==========================================
    # 3. Separate Case and Control Samples
    # ==========================================
    case_samples <- methy[, methy\$status == "case"]
    control_samples <- methy[, methy\$status == "control"]
    
    # ==========================================
    # 4. Run Epimutation Detection
    # ==========================================
    # Identify epimutations using the MANOVA method
    epi_mvo <- epimutations(case_samples, control_samples, method = "manova")
    
    # Save identified epimutations
    write.csv(as.data.frame(epi_mvo), "identified_epimutations.csv", row.names = FALSE)
    
    # ==========================================
    # 5. Annotate Identified Epimutations
    # ==========================================
    # Enrich epimutations with genomic and OMIM annotations
    rst_mvo <- annotate_epimutations(epi_mvo, omim = TRUE)
    
    # Save annotated epimutations
    write.csv(as.data.frame(rst_mvo), "annotated_epimutations.csv", row.names = FALSE)
    
    # ==========================================
    # 6. Visualize Epimutations
    # ==========================================
    # Open PDF device to save visualization plots
    pdf("epimutations_visualization.pdf", width = 11, height = 8.5)
    
    # Plot 1: Default epimutation plot for the first identified epimutation
    tryCatch({
      p1 <- plot_epimutations(as.data.frame(epi_mvo[1,]), methy)
      if (!is.null(p1)) {
        plot(p1)
      }
    }, error = function(e) {
      message("Could not generate default plot: ", e\$message)
    })
    
    # Plot 2: Epimutation plot with gene annotations
    tryCatch({
      p2 <- plot_epimutations(as.data.frame(epi_mvo[1,]), methy = methy, genes_annot = TRUE)
      plot(p2)
    }, error = function(e) {
      message("Could not generate gene-annotated plot: ", e\$message)
    })
    
    # Plot 3: Epimutation plot with chromatin/regulation marks
    tryCatch({
      p3 <- plot_epimutations(as.data.frame(epi_mvo[1,]), methy = methy, regulation = TRUE)
      plot(p3)
    }, error = function(e) {
      message("Could not generate regulation plot: ", e\$message)
    })
    
    # Close PDF device
    dev.off()

    writeLines(c(
        '"BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS":',
        paste0('    epimutacions: ', as.character(packageVersion('epimutacions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_case_control_epimutation_analysis.csv versions.yml
    """
}

workflow BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ baseDir, reference_panel, methy ] ]

    main:
    BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS.out.tables
    plots    = BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS.out.plots
    objects  = BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS.out.objects
    versions = BIOC_EPIMUTACIONS_CASE_CONTROL_EPIMUTATION_ANALYSIS.out.versions
}
