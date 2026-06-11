#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClusterSignificance — pcp_analysis
// Assess class cluster separation in multi-dimensional space (or with more than 2 classes) using Principal Curve Projection.
// Input: pcpMatrix, classes
// Container: quay.io/biocontainers/bioconductor-clustersignificance:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ClusterSignificance
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Project data onto a principal curve using pcp
//  * 2. [Core Analysis] Classify and score the separation using classify
//  * 3. [Core Analysis] Run permutation testing using permute
//  * 4. [Core Analysis] Extract p-values and confidence intervals using pvalue and conf.int

nextflow.enable.dsl = 2

process BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(ClusterSignificance)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read pcpMatrix
    if (file.exists("pcpMatrix.rds")) {
        pcpMatrix <- readRDS("pcpMatrix.rds")
    } else if (file.exists("pcpMatrix.csv")) {
        pcpMatrix <- as.matrix(read.csv("pcpMatrix.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("pcpMatrix")) {
        pcpMatrix <- as.matrix(read.table("pcpMatrix", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
        stop("Error: pcpMatrix file not found in the working directory.")
    }
    
    # Read classes
    if (file.exists("classes.rds")) {
        classes_input <- readRDS("classes.rds")
    } else if (file.exists("classes.txt")) {
        classes_input <- readLines("classes.txt")
    } else if (file.exists("classes")) {
        classes_input <- readLines("classes")
    } else if (file.exists("classes.csv")) {
        classes_input <- read.csv("classes.csv", header = FALSE, stringsAsFactors = FALSE)[[1]]
    } else {
        stop("Error: classes file not found in the working directory.")
    }
    
    # Ensure classes match the rows of pcpMatrix
    if (length(classes_input) != nrow(pcpMatrix)) {
        stop("Error: The length of classes does not match the number of rows in pcpMatrix.")
    }
    
    # Align with the documented code's expectation that classes are stored in rownames
    rownames(pcpMatrix) <- classes_input
    
    # -----------------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # -----------------------------------------------------------------------------
    
    # Create the group variable as documented
    classes <- rownames(pcpMatrix)
    
    # Stage 1: Project data onto a principal curve using pcp
    prj <- pcp(pcpMatrix, classes)
    
    # Save projection plot
    pdf("pcp_projection_plot.pdf", width = 10, height = 10)
    plot(prj)
    dev.off()
    
    # Stage 2: Classify and score the separation using classify
    cl <- classify(prj)
    
    # Save classification plot
    pdf("classification_plot.pdf", width = 10, height = 7)
    plot(cl)
    dev.off()
    
    # Extract AUC and save to CSV
    auc_values <- getData(cl, "AUC")
    write.csv(as.data.frame(auc_values), "auc_results.csv", row.names = TRUE)
    
    # Stage 3: Run permutation testing using permute
    iterations <- 100
    pe <- permute(
        mat = pcpMatrix, 
        iter = iterations, 
        classes = classes, 
        projmethod = "pcp"
    )
    
    # Save permutation plot
    pdf("permutation_plot.pdf", width = 10, height = 7)
    plot(pe)
    dev.off()
    
    # Stage 4: Extract p-values and confidence intervals
    p_vals <- pvalue(pe)
    write.csv(as.data.frame(p_vals), "pvalues_results.csv", row.names = TRUE)
    
    conf_intervals <- conf.int(pe, conf.level = .99)
    write.csv(as.data.frame(conf_intervals), "confidence_intervals.csv", row.names = TRUE)
    
    # Save R objects for downstream analysis
    saveRDS(prj, "pcp_projection.rds")
    saveRDS(cl, "classification.rds")
    saveRDS(pe, "permutation_results.rds")

    writeLines(c(
        '"BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS":',
        paste0('    ClusterSignificance: ', as.character(packageVersion('ClusterSignificance')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcp_analysis.csv versions.yml
    """
}

workflow BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pcpMatrix, classes ] ]

    main:
    BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS.out.tables
    plots    = BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS.out.plots
    objects  = BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS.out.objects
    versions = BIOC_CLUSTERSIGNIFICANCE_PCP_ANALYSIS.out.versions
}
