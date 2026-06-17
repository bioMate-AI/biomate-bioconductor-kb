#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rrvgo — reduce_and_visualize_go_redundancy
// Reduce redundancy in a list of enriched Gene Ontology (GO) terms using semantic similarity and visualize the grouped terms.
// Input: go_analysis.txt
// Container: quay.io/biocontainers/bioconductor-rrvgo:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: org.Hs.eg.db, rrvgo
// Visualizations: heatmap, scatter plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the semantic similarity matrix using calculateSimMatrix
//  * 2. [Core Analysis] Transform q-values to scores and reduce the similarity matrix using reduceSimMatrix
//  * 3. [Visualization & Output] Visualize the reduced terms using heatmapPlot, scatterPlot, treemapPlot, and wordcloudPlot

nextflow.enable.dsl = 2

process BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY {
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
    .bm_deps <- c("rrvgo", "org.Hs.eg.db")
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
        
        # Load required libraries
        library(rrvgo)
        library(org.Hs.eg.db)
        
        # Read the user input file from the working directory
        # The file must be tab-delimited and contain 'ID' (GO term IDs) and 'qvalue' columns
        go_analysis <- read.delim("go_analysis.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        
        # 1. Calculate the semantic similarity matrix
        simMatrix <- calculateSimMatrix(go_analysis\$ID,
                                        orgdb="org.Hs.eg.db",
                                        ont="BP",
                                        method="Rel")
        
        # 2. Transform q-values to scores and reduce the similarity matrix
        scores <- setNames(-log10(go_analysis\$qvalue), go_analysis\$ID)
        reducedTerms <- reduceSimMatrix(simMatrix,
                                        scores,
                                        threshold=0.7,
                                        orgdb="org.Hs.eg.db")
        
        # Save tabular results and RDS objects
        write.csv(reducedTerms, "reduced_terms.csv", row.names = FALSE)
        saveRDS(simMatrix, "similarity_matrix.rds")
        saveRDS(reducedTerms, "reduced_terms.rds")
        
        # 3. Visualize the reduced terms and save plots to PDF files
        
        # Heatmap Plot
        pdf("heatmap.pdf", width = 10, height = 8)
        heatmapPlot(simMatrix,
                    reducedTerms,
                    annotateParent=TRUE,
                    annotationLabel="parentTerm",
                    fontsize=6)
        dev.off()
        
        # Scatter Plot
        pdf("scatterplot.pdf", width = 8, height = 8)
        print(scatterPlot(simMatrix, reducedTerms))
        dev.off()
        
        # Treemap Plot
        pdf("treemap.pdf", width = 8, height = 8)
        treemapPlot(reducedTerms)
        dev.off()
        
        # Wordcloud Plot
        pdf("wordcloud.pdf", width = 8, height = 8)
        wordcloudPlot(reducedTerms, min.freq=1, colors="black")
        dev.off()

    writeLines(c(
        '"BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY":',
        paste0('    rrvgo: ', as.character(packageVersion('rrvgo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reduce_and_visualize_go_redundancy.csv versions.yml
    """
}

workflow BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ go_analysis.txt ] ]

    main:
    BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY(ch_input)

    emit:
    tables   = BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY.out.tables
    plots    = BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY.out.plots
    objects  = BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY.out.objects
    versions = BIOC_RRVGO_REDUCE_AND_VISUALIZE_GO_REDUNDANCY.out.versions
}
