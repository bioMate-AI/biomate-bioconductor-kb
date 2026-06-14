#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fedup — pathway_enrichment_and_depletion_analysis
// Test one or more gene sets against a background for pathway enrichment and depletion using Fisher's exact test, visualize with a dot plot, and generate an enric
// Input: gene_list.rds, pathways.gmt
// Container: quay.io/biocontainers/bioconductor-fedup:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, fedup, ggplot2, tidyr
// Visualizations: dot plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the enrichment/depletion analysis using runFedup
//  * 2. [Core Analysis] Format and filter results using dplyr and tidyr
//  * 3. [Visualization & Output] Plot significant results using plotDotPlot
//  * 4. [Visualization & Output] Write out formatted results for EnrichmentMap using writeFemap
//  * 5. [Visualization & Output] Write out pathway annotations to GMT format using writePathways
//  * 6. [Visualization & Output] Generate and visualize the enrichment map in Cytoscape using plotFemap

nextflow.enable.dsl = 2

process BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("fedup", "dplyr", "tidyr", "ggplot2")
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
    library(fedup)
    library(dplyr)
    library(tidyr)
    library(ggplot2)
    
    # 1. Read user input files
    # gene_list.rds is a named list containing 'background' and one or more test sets
    geneDouble <- readRDS("gene_list.rds")
    
    # pathways.gmt is a pathway annotation file in GMT format
    pathwaysGMT <- readPathways("pathways.gmt")
    
    # 2. Run the enrichment/depletion analysis using runFedup
    fedupRes <- runFedup(geneDouble, pathwaysGMT)
    
    # Save the raw results to RDS
    saveRDS(fedupRes, "fedup_results.rds")
    
    # 3. Format and filter results using dplyr and tidyr
    fedupPlot <- fedupRes %>%
        bind_rows(.id = "set") %>%
        separate(col = "set", into = c("set", "sign"), sep = "_") %>%
        subset(qvalue < 0.05) %>%
        mutate(log10qvalue = -log10(qvalue)) %>%
        mutate(pathway = gsub("\\%.*", "", pathway)) %>%
        as.data.frame()
    
    # Save formatted plot data to CSV
    write.csv(fedupPlot, "fedup_plot_data.csv", row.names = FALSE)
    
    # 4. Plot significant results using plotDotPlot
    p <- plotDotPlot(
            df = fedupPlot,
            xVar = "log10qvalue",
            yVar = "pathway",
            xLab = "-log10(qvalue)",
            fillVar = "sign",
            fillLab = "Genetic interaction",
            fillCol = c("#6D90CA", "#F6EB13"),
            sizeVar = "fold_enrichment",
            sizeLab = "Fold enrichment") +
        facet_grid("sign", scales = "free", space = "free") +
        theme(strip.text.y = element_blank())
    
    # Save the plot to PDF
    ggsave("fedup_dotplot.pdf", plot = p, width = 11, height = 15.5)
    
    # 5. Write out formatted results for EnrichmentMap using writeFemap
    resultsFolder <- tempdir()
    writeFemap(fedupRes, resultsFolder)
    
    # Copy the written files to the working directory for user access
    femap_files <- list.files(resultsFolder, pattern = "^femap_.*\\\\.txt\$", full.names = TRUE)
    if (length(femap_files) > 0) {
        file.copy(femap_files, ".", overwrite = TRUE)
    }
    
    # 6. Write out pathway annotations to GMT format using writePathways
    gmtFile <- tempfile("pathwaysGMT", fileext = ".gmt")
    writePathways(pathwaysGMT, gmtFile)
    file.copy(gmtFile, "pathways_output.gmt", overwrite = TRUE)
    
    # 7. Generate and visualize the enrichment map in Cytoscape using plotFemap
    netFile <- tempfile("fedupEM_geneDouble", fileext = ".png")
    
    # Wrap in tryCatch since Cytoscape must be running locally for plotFemap to succeed
    tryCatch({
        plotFemap(
            gmtFile = gmtFile,
            resultsFolder = resultsFolder,
            qvalue = 0.05,
            chartData = "DATA_SET",
            hideNodeLabels = TRUE,
            netName = "fedupEM_geneDouble",
            netFile = netFile
        )
        if (file.exists(netFile)) {
            file.copy(netFile, "fedupEM_geneDouble.png", overwrite = TRUE)
        }
    }, error = function(e) {
        message("Note: plotFemap failed (this is expected if Cytoscape is not running). Error: ", e\$message)
    })

    writeLines(c(
        '"BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS":',
        paste0('    fedup: ', as.character(packageVersion('fedup')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_enrichment_and_depletion_analysis.csv versions.yml
    """
}

workflow BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_list.rds, pathways.gmt ] ]

    main:
    BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS.out.tables
    plots    = BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS.out.plots
    objects  = BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS.out.objects
    versions = BIOC_FEDUP_PATHWAY_ENRICHMENT_AND_DEPLETION_ANALYSIS.out.versions
}
