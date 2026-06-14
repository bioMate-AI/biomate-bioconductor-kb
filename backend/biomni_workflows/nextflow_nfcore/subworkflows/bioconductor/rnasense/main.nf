#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RNAsense — time_resolved_rnaseq_analysis
// Compare RNA-seq time curves between two conditions to identify differential expression and expression switches over time.
// Input: SummarizedExperiment
// Container: quay.io/biocontainers/bioconductor-rnasense:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RNAsense, SummarizedExperiment, ggplot2
// Visualizations: volcano plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and filter data
//  * 2. [Core Analysis] Perform fold change analysis at each time point
//  * 3. [Core Analysis] Detect expression switches over time
//  * 4. [Core Analysis] Combine fold change and switch results
//  * 5. [Visualization & Output] Visualize stage-specific gene sets
//  * 6. [Visualization & Output] Export results to text files

nextflow.enable.dsl = 2

process BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS {
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
    .bm_deps <- c("RNAsense", "ggplot2", "SummarizedExperiment")
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
        
    # Load required librarie    library(SummarizedExperiment)
s
    library(RNAsense)
    library(ggplot2)
    
    # ==========================================
    # 1. Load and filter data
    # ==========================================
    
    # Read the user-provided SummarizedExperiment object
    input_file <- "summarized_experiment.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    mydata <- readRDS(input_file)
    
    # Ensure the object is a SummarizedExperiment
    if (!inherits(mydata, "SummarizedExperiment")) {
      stop("Error: The input file must contain a SummarizedExperiment object.")
    }
    
    # Define analysis parameters dynamically from the data
    analyzeConditions <- unique(as.character(colData(mydata)\$condition))
    thCount <- 100
    nrcores <- 1
    
    # Set cores to 1 on Windows to avoid parallelization issues
    if (Sys.info()[[1]] == "Windows") {
      nrcores <- 1
    }
    
    # Filter out low-expression genes
    vec2Keep <- which(vapply(1:dim(mydata)[1], function(i) {
      !Reduce("&", assays(mydata)[[1]][i, ] < thCount)
    }, TRUE))
    mydata <- mydata[vec2Keep, ]
    
    # Get unique sorted measurement times from input data
    times <- unique(sort(as.numeric(colData(mydata)\$time)))
    
    # ==========================================
    # 2. Perform fold change analysis at each time point
    # ==========================================
    
    resultFC <- getFC(dataset = mydata, 
                      myanalyzeConditions = analyzeConditions, 
                      cores = nrcores, 
                      mytimes = times)
    
    # Save fold change results
    write.csv(resultFC, file = "result_fold_change.csv", row.names = FALSE)
    
    # Visualize fold change results (Volcano Plot)
    volcano_plot <- ggplot(subset(resultFC, FCdetect != "none"), 
                           aes(x = logFoldChange, y = -log10(pValue), color = FCdetect)) + 
      xlab("log2(Fold Change)") + 
      geom_point(shape = 20)
    
    ggsave("volcano_plot.pdf", plot = volcano_plot, width = 7, height = 4.5)
    
    # ==========================================
    # 3. Detect expression switches over time
    # ==========================================
    
    resultSwitch <- getSwitch(dataset = mydata,
                              experimentStepDetection = analyzeConditions[1],
                              cores = nrcores,
                              mytimes = times)
    
    # Save switch detection results
    write.csv(resultSwitch, file = "result_switch.csv", row.names = FALSE)
    
    # ==========================================
    # 4. Combine fold change and switch results
    # ==========================================
    
    resultCombined <- combineResults(resultSwitch, resultFC)
    saveRDS(resultCombined, file = "result_combined.rds")
    
    # ==========================================
    # 5. Visualize stage-specific gene sets
    # ==========================================
    
    pdf("ssgs_heatmap.pdf", width = 7, height = 5)
    plotSSGS(resultCombined, times[-length(times)])
    dev.off()
    
    # ==========================================
    # 6. Export results to text files
    # ==========================================
    
    # This function automatically writes 5 text files to the working directory:
    # - geneNamelist_switchUp.txt
    # - geneNamelist_switchDown.txt
    # - genelist_switchUp.txt
    # - genelist_switchDown.txt
    # - switchList.txt
    outputGeneTables(resultCombined)
    
    message("Pipeline completed successfully. Outputs generated in the working directory.")

    writeLines(c(
        '"BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS":',
        paste0('    RNAsense: ', as.character(packageVersion('RNAsense')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_resolved_rnaseq_analysis.csv versions.yml
    """
}

workflow BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment ] ]

    main:
    BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.tables
    plots    = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.plots
    objects  = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.objects
    versions = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.versions
}
