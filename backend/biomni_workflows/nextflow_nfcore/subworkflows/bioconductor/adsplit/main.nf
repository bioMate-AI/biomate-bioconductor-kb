#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adSplit — annotation_driven_clustering
// Perform annotation-driven class discovery on expression data using GO/KEGG annotations, compute empirical significance, and visualize the resulting patient spli
// Input: ExpressionSet object, Character string
// Container: quay.io/biocontainers/bioconductor-adsplit:1.80.0--r45ha27e39d_0
// R packages: Biobase, adSplit, anno_pkg, golubesets
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, adSplit
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run adSplit to generate splits for specific terms or entire ontologies ("GO", "KEGG", "all") with permutation testing to compute e
//  * 2. [Visualization & Output] Summarize the resulting splitSet object
//  * 3. [Visualization & Output] Plot a histogram of empirical p-values and corrected q-values
//  * 4. [Visualization & Output] Generate a clustered heatmap image of the significant splits filtered by FDR

nextflow.enable.dsl = 2

process BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("Biobase", "adSplit", "anno_pkg", "golubesets")
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
    library(adSplit)
    library(Biobase)
    
    # Read user input files from the working directory
    eset <- readRDS("expression_set.rds")
    anno_pkg <- readLines("annotation_package.txt", warn = FALSE)[1]
    
    # Dynamically load the chip-specific annotation metadata package
    if (!requireNamespace(anno_pkg, quietly = TRUE)) {
      stop(paste("Required annotation package", anno_pkg, "is not installed."))
    }
    library(anno_pkg, character.only = TRUE)
    
    # Stage 1: Run adSplit to generate splits for specific terms with permutation testing
    glutamSplits <- adSplit(eset, "KEGG:00251", anno_pkg, B = 1000)
    print(glutamSplits)
    saveRDS(glutamSplits, "glutamSplits.rds")
    
    # Run adSplit for specific GO terms with max.probes filter
    x_go <- adSplit(eset, c("GO:0007165", "GO:0006915"), anno_pkg, max.probes = 7000)
    print(x_go)
    saveRDS(x_go, "x_go.rds")
    
    # Run adSplit for entire KEGG pathway set with permutation testing to compute empirical p-values
    # (We use B=100 to ensure a timely run while still generating the necessary q-values)
    keggSplits <- adSplit(eset, "KEGG", anno_pkg, B = 100)
    print(keggSplits)
    saveRDS(keggSplits, "keggSplits.rds")
    
    # Stage 2: Summarize the resulting splitSet object
    qval_summary <- summary(keggSplits\$qvalues)
    print(qval_summary)
    
    # Save summary to a CSV file
    write.csv(as.data.frame(as.list(qval_summary)), "keggSplits_qvalues_summary.csv", row.names = FALSE)
    
    # Stage 3: Plot a histogram of empirical p-values and corrected q-values
    pdf("hist_keggSplits.pdf")
    hist(keggSplits)
    dev.off()
    
    # Stage 4: Generate a clustered heatmap image of the significant splits filtered by FDR
    # The image function in adSplit writes directly to the specified outfile
    image(keggSplits, filter.fdr = 0.3, outfile = "splitSet.eps", res = 300)

    writeLines(c(
        '"BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING":',
        paste0('    adSplit: ', as.character(packageVersion('adSplit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotation_driven_clustering.csv versions.yml
    """
}

workflow BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet object, Character string ] ]

    main:
    BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING.out.tables
    plots    = BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING.out.plots
    objects  = BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING.out.objects
    versions = BIOC_ADSPLIT_ANNOTATION_DRIVEN_CLUSTERING.out.versions
}
