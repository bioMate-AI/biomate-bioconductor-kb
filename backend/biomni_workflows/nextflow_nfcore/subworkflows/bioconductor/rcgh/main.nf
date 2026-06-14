#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rcgh — acgh_analysis_pipeline
// Perform a complete aCGH analysis pipeline from reading raw array data to signal adjustment, segmentation, EM normalization, gene annotation, and visualization.
// Input: Affy_cytoScan.cyhd.CN5.CNCHP.txt.bz2, Affy_snp6_cnchp.txt.bz2, Agilent4x180K.txt.bz2, generic.txt.bz2
// Container: quay.io/biocontainers/bioconductor-rcgh:1.40.0--r45hdfd78af_0
// R packages: rCGH
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: profile plot, density plot

nextflow.enable.dsl = 2

process BIOC_RCGH_ACGH_ANALYSIS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rcgh:1.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("rCGH")
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
    
    # Load the required library
    library(rCGH)
    
    # Define the input file paths in the working directory
    file_cytoScan <- "Affy_cytoScan.cyhd.CN5.CNCHP.txt.bz2"
    file_snp6     <- "Affy_snp6_cnchp.txt.bz2"
    file_agilent  <- "Agilent4x180K.txt.bz2"
    file_generic  <- "generic.txt.bz2"
    
    # Read the primary CytoScan file for the main workflow
    cgh <- readAffyCytoScan(file_cytoScan, sampleName = "CSc-Example", labName = "myLab")
    
    # Read the other required user input files to satisfy the pipeline input requirements
    tryCatch({
        cgh_snp6 <- readAffySNP6(file_snp6, sampleName = "SNP6-Example", labName = "myLab")
    }, error = function(e) {
        warning("Could not read SNP6 file: ", e\$message)
    })
    
    tryCatch({
        cgh_agilent <- readAgilent(file_agilent, sampleName = "Agilent-Example", labName = "myLab")
    }, error = function(e) {
        warning("Could not read Agilent file: ", e\$message)
    })
    
    tryCatch({
        cgh_generic <- readGeneric(file_generic, sampleName = "Generic-Example", labName = "myLab")
    }, error = function(e) {
        warning("Could not read Generic file: ", e\$message)
    })
    
    # Print the primary cgh object
    print(cgh)
    
    # Set and get sample annotations
    setInfo(cgh, "item1") <- 35
    setInfo(cgh, "item2") <- TRUE
    setInfo(cgh, "item3") <- "someComment"
    
    print(getInfo(cgh))
    print(getInfo(cgh, c("item1", "item3")))
    
    # Adjust and scale LRR signals
    cgh <- adjustSignal(cgh, nCores=1)
    
    # Segment genomic profile and extract the segmentation table
    cgh <- segmentCGH(cgh, nCores=1)
    segTable <- getSegTable(cgh)
    print(head(segTable))
    
    # Write the segmentation table to a CSV file
    write.csv(segTable, "segmentation_table.csv", row.names = FALSE)
    
    # Center LRR using EM normalization
    cgh <- EMnormalize(cgh)
    
    # Plot density and save to a PDF file
    pdf("density_plot.pdf", width = 7, height = 5)
    plotDensity(cgh)
    dev.off()
    
    # Map segments to genes
    geneTable <- byGeneTable(segTable)
    print(head(geneTable, n=3))
    write.csv(geneTable, "gene_table_hg19.csv", row.names = FALSE)
    
    # Query specific genes for hg19 and hg18 builds
    erbb2_hg19 <- byGeneTable(segTable, "erbb2", genome = "hg19")[,1:6]
    print(erbb2_hg19)
    write.csv(erbb2_hg19, "erbb2_hg19.csv", row.names = FALSE)
    
    erbb2_hg18 <- byGeneTable(segTable, "erbb2", genome = "hg18")[,1:6]
    print(erbb2_hg18)
    write.csv(erbb2_hg18, "erbb2_hg18.csv", row.names = FALSE)
    
    # Access analysis parameters
    print(getParam(cgh)[1:3])
    
    # Visualize profile statically using multiplot and save to a PDF file
    pdf("multiplot_profile.pdf", width = 8, height = 10)
    multiplot(cgh, symbol = c("egfr", "erbb2"))
    dev.off()
    
    # Recentering the profile on peak #2
    recenter(cgh) <- 2
    
    # Plot the recentered profile and save to a PDF file
    pdf("recentered_profile.pdf", width = 8, height = 5)
    plotProfile(cgh, symbol = c("egfr", "erbb2"))
    dev.off()
    
    # Save the final analyzed rCGH object
    saveRDS(cgh, "cgh_analyzed.rds")

    writeLines(c(
        '"BIOC_RCGH_ACGH_ANALYSIS_PIPELINE":',
        paste0('        rcgh: ', as.character(packageVersion("rcgh")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acgh_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_RCGH_ACGH_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Affy_cytoScan.cyhd.CN5.CNCHP.txt.bz2, Affy_snp6_cnchp.txt.bz2, Agilent4x180K.txt.bz2, generic.txt.bz2 ] ]

    main:
    BIOC_RCGH_ACGH_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RCGH_ACGH_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_RCGH_ACGH_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_RCGH_ACGH_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_RCGH_ACGH_ANALYSIS_PIPELINE.out.versions
}
