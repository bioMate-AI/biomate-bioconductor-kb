#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nanostringnctools — nanostring_ncounter_analysis
// Read raw NanoString RCC/RLF files, perform quality control, normalize counts, and visualize results.
// Input: rcc_files, rlf_file, sample_annotation
// Container: quay.io/biocontainers/bioconductor-nanostringnctools:1.18.0--r45hdfd78af_0
// R packages: ggiraph, ggplot2, ggthemes, htmlwidgets, NanoStringNCTools, pheatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nanostringnctools:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggiraph", "ggplot2", "ggthemes", "htmlwidgets", "NanoStringNCTools", "pheatmap")
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
    
    #===============================================================================
    # Pipeline: nanostring_ncounter_analysis
    # Description: Read raw NanoString RCC/RLF files, perform quality control,
    #              normalize counts, and visualize results.
    #===============================================================================
    
    library(NanoStringNCTools)
    library(ggthemes)
    library(ggiraph)
    library(pheatmap)
    library(ggplot2)
    library(htmlwidgets)
    
    #-------------------------------------------------------------------------------
    # 1. Locate and Validate User Input Files in the Working Directory
    #-------------------------------------------------------------------------------
    
    # Search for RCC files in the current working directory
    rcc_files <- list.files(path = ".", pattern = "\\\\.RCC\$", ignore.case = TRUE, full.names = TRUE)
    
    # Search for the RLF file in the current working directory
    rlf_file <- list.files(path = ".", pattern = "\\\\.rlf\$", ignore.case = TRUE, full.names = TRUE)[1]
    
    # Search for the sample annotation CSV file in the current working directory
    sample_annotation <- list.files(path = ".", pattern = "pheno|annotation.*\\\\.csv\$", ignore.case = TRUE, full.names = TRUE)[1]
    
    # Validate that all required inputs are present
    if (length(rcc_files) == 0) {
      stop("Error: No RCC files found in the working directory.")
    }
    if (is.na(rlf_file) || !file.exists(rlf_file)) {
      stop("Error: RLF file not found in the working directory.")
    }
    if (is.na(sample_annotation) || !file.exists(sample_annotation)) {
      stop("Error: Sample annotation CSV file not found in the working directory.")
    }
    
    message(paste("Found", length(rcc_files), "RCC files."))
    message(paste("Using RLF file:", rlf_file))
    message(paste("Using sample annotation:", sample_annotation))
    
    #-------------------------------------------------------------------------------
    # 2. Load Raw Data and Initialize NanoStringRCCSet
    #-------------------------------------------------------------------------------
    
    demoData <- readNanoStringRccSet(rcc_files, rlfFile = rlf_file, phenoDataFile = sample_annotation)
    
    #-------------------------------------------------------------------------------
    # 3. Assign Design and Adjust Dimension Labels
    #-------------------------------------------------------------------------------
    
    design(demoData) <- ~ `Treatment`
    protocolData(demoData)[["Sample ID"]] <- sampleNames(demoData)
    dimLabels(demoData)[2] <- "Sample ID"
    
    #-------------------------------------------------------------------------------
    # 4. Quality Control Flagging and Visualization
    #-------------------------------------------------------------------------------
    
    demoData <- setQCFlags(demoData,
                           qcCutoffs = list(Housekeeper = c(failingCutoff = 32, passingCutoff = 100), 
                                            Imaging = c(fovCutoff = 0.75), 
                                            BindingDensity = c(minimumBD = 0.1, maximumBD = 2.25, maximumBDSprint = 1.8), 
                                            ERCCLinearity = c(correlationValue = 0.95), 
                                            ERCCLoD = c(standardDeviations = 2)))
    
    # Generate and save interactive QC plots as HTML widgets
    htmlwidgets::saveWidget(girafe(ggobj = autoplot(demoData, type = "housekeep-geom")), "qc_housekeep_geom.html")
    htmlwidgets::saveWidget(girafe(ggobj = autoplot(demoData, type = "lane-bindingDensity")), "qc_lane_bindingDensity.html")
    htmlwidgets::saveWidget(girafe(ggobj = autoplot(demoData, type = "lane-fov")), "qc_lane_fov.html")
    htmlwidgets::saveWidget(girafe(ggobj = autoplot(demoData, type = "ercc-linearity")), "qc_ercc_linearity.html")
    
    # Also save static versions of the QC plots to a single PDF
    pdf("qc_plots_summary.pdf", width = 8, height = 6)
    print(autoplot(demoData, type = "housekeep-geom"))
    print(autoplot(demoData, type = "lane-bindingDensity"))
    print(autoplot(demoData, type = "lane-fov"))
    print(autoplot(demoData, type = "ercc-linearity"))
    dev.off()
    
    #-------------------------------------------------------------------------------
    # 5. Subset Data (Extract Negative Controls)
    #-------------------------------------------------------------------------------
    
    neg_set <- negativeControlSubset(demoData)
    
    #-------------------------------------------------------------------------------
    # 6. Normalization
    #-------------------------------------------------------------------------------
    
    demoData <- normalize(demoData, type="nSolver", fromELT = "exprs", toELT = "exprs_norm")
    
    #-------------------------------------------------------------------------------
    # 7. Visualization of Normalized Expression (Heatmap)
    #-------------------------------------------------------------------------------
    
    pdf("heatmap_normalized_genes.pdf", width = 10, height = 8)
    print(autoplot(demoData, type = "heatmap-genes", elt = "exprs_norm", heatmapGroup = c("Treatment", "BRAFGenotype"), 
             show_colnames_gene_limit = 10, show_rownames_gene_limit = 40,
             log2scale = FALSE))
    dev.off()
    
    #-------------------------------------------------------------------------------
    # 8. Transform and Export Results
    #-------------------------------------------------------------------------------
    
    # Munge negative controls
    neg_ctrls <- munge(neg_set, ~exprs)
    write.csv(neg_ctrls, "negative_controls_expression.csv", row.names = FALSE)
    
    # Transform normalized expression matrix to data frame
    exprs_df <- transform(assayData(demoData)[["exprs_norm"]])
    write.csv(exprs_df, "normalized_expression_matrix.csv", row.names = TRUE)
    
    # Save the complete normalized NanoStringRCCSet object
    saveRDS(demoData, "normalized_demoData.rds")
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS":',
        paste0('        nanostringnctools: ', as.character(packageVersion("nanostringnctools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nanostring_ncounter_analysis.csv versions.yml
    """
}

workflow BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rcc_files, rlf_file, sample_annotation ] ]

    main:
    BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS.out.tables
    plots    = BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS.out.plots
    objects  = BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS.out.objects
    versions = BIOC_NANOSTRINGNCTOOLS_NANOSTRING_NCOUNTER_ANALYSIS.out.versions
}
