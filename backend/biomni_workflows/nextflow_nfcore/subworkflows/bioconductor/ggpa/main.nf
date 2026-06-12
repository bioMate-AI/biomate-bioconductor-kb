#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GGPA — standard_graph_gpa
// Fit a graph-GPA model to multiple GWAS p-value datasets to perform association mapping and estimate the phenotype graph without prior knowledge.
// Input: pmat
// Container: quay.io/biocontainers/bioconductor-ggpa:1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GGPA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the graph-GPA model using GGPA
//  * 2. [Core Analysis] Extract parameter estimates using estimates
//  * 3. [Core Analysis] Perform marginal and joint association mapping using assoc
//  * 4. [Core Analysis] Calculate local FDR using fdr
//  * 5. [Visualization & Output] Visualize the estimated phenotype graph using plot

nextflow.enable.dsl = 2

process BIOC_GGPA_STANDARD_GRAPH_GPA {
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
    .bm_deps <- c("GGPA")
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
        
        # Load required library
        library(GGPA)
        
        # Read user input 'pmat'
        # The script checks for pmat.rds, pmat.csv, pmat.tsv, or a plain file named 'pmat'
        if (file.exists("pmat.rds")) {
          pmat <- readRDS("pmat.rds")
        } else if (file.exists("pmat.csv")) {
          pmat <- as.matrix(read.csv("pmat.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("pmat.tsv")) {
          pmat <- as.matrix(read.delim("pmat.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("pmat")) {
          pmat <- as.matrix(read.table("pmat", header = TRUE, row.names = 1, check.names = FALSE))
        } else {
          stop("Error: Required input file 'pmat' (matrix of GWAS p-values) not found in the working directory.")
        }
        
        # Ensure pmat is a numeric matrix
        pmat <- as.matrix(pmat)
        storage.mode(pmat) <- "numeric"
        
        # 1. Fit the graph-GPA model using GGPA
        set.seed(12345)
        fit <- GGPA( pmat, nBurnin=10000, nMain=40000 )
        
        # Display fit summary
        fit
        
        # Save the fitted model object
        saveRDS(fit, "ggpa_fit.rds")
        
        # 2. Extract parameter estimates using estimates
        fit_estimates <- estimates(fit)
        str(fit_estimates)
        saveRDS(fit_estimates, "estimates.rds")
        
        # 3. Perform marginal association mapping using assoc
        assoc.marg <- assoc( fit, FDR=0.10, fdrControl="global" )
        dim(assoc.marg)
        apply( assoc.marg, 2, table )
        write.csv(assoc.marg, "assoc_marginal.csv", row.names = TRUE)
        
        # 4. Calculate local FDR using fdr
        fdr.marg <- fdr(fit)
        dim(fdr.marg)
        head(fdr.marg)
        write.csv(fdr.marg, "fdr_marginal.csv", row.names = TRUE)
        
        # 5. Perform joint association mapping using assoc
        assoc.joint <- assoc( fit, FDR=0.10, fdrControl="global", i=1, j=2 )
        length(assoc.joint)
        head(assoc.joint)
        table(assoc.joint)
        
        # Save joint association results
        write.csv(data.frame(assoc_joint = assoc.joint), "assoc_joint.csv", row.names = TRUE)
        
        # 6. Visualize the estimated phenotype graph using plot
        pdf("phenotype_graph.pdf")
        plot(fit)
        dev.off()

    writeLines(c(
        '"BIOC_GGPA_STANDARD_GRAPH_GPA":',
        paste0('    GGPA: ', as.character(packageVersion('GGPA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_graph_gpa.csv versions.yml
    """
}

workflow BIOC_GGPA_STANDARD_GRAPH_GPA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pmat ] ]

    main:
    BIOC_GGPA_STANDARD_GRAPH_GPA(ch_input)

    emit:
    tables   = BIOC_GGPA_STANDARD_GRAPH_GPA.out.tables
    plots    = BIOC_GGPA_STANDARD_GRAPH_GPA.out.plots
    objects  = BIOC_GGPA_STANDARD_GRAPH_GPA.out.objects
    versions = BIOC_GGPA_STANDARD_GRAPH_GPA.out.versions
}
