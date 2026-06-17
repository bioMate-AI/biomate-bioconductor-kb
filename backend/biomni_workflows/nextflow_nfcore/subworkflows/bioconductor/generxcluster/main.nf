#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneRxCluster — differential_clustering_analysis
// Detect and analyze genomic regions with differential clustering of integration sites between two groups.
// Input: exptData.txt
// Container: quay.io/biocontainers/bioconductor-generxcluster:1.46.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: geneRxCluster
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read genomic site data from a file
//  * 2. [Core Analysis] Run the differential clustering analysis using gRxCluster
//  * 3. [Visualization & Output] Summarize the discovered clusters and false discovery rate using gRxSummary
//  * 4. [Visualization & Output] Plot the critical regions using gRxPlot
//  * 5. [Core Analysis] (Optional) Customize critical regions and filters to optimize discovery power

nextflow.enable.dsl = 2

process BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS {
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
    .bm_deps <- c("geneRxCluster")
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
    library(geneRxCluster)
    
    # 1. Read genomic site data from a file
    df <- read.table("exptData.txt", header=TRUE)
    
    # Ensure positions are sorted within each chromosome (critical pitfall for geneRxCluster)
    df <- df[order(df\$chromo, df\$pos), ]
    
    # 2. Run the differential clustering analysis using gRxCluster
    null.results <-
        gRxCluster(df\$chromo,df\$pos,df\$grp,15L:30L,nperm=100L)
    
    # 3. Summarize the discovered clusters and false discovery rate using gRxSummary
    null_summary <- gRxSummary( null.results )
    capture.output(print(null_summary), file="null_summary.txt")
    
    # Set up variables for subsequent steps using the input data
    df3 <- df
    alt.results <- null.results
    
    # 4. Plot the critical regions using gRxPlot
    pdf("critical_regions_plot.pdf", width=8, height=6)
    gRxPlot(alt.results,method="criticalRegions")
    dev.off()
    
    # 5. Customize critical regions and filters to optimize discovery power
    generous.target.expr <-
        quote(critVal.target(k,n, target=20, posdiff=x))
    generous.results <-
        gRxCluster(df3\$chromo,df3\$pos,df3\$grp,
    	       15L:30L,nperm=100L,
    	       cutpt.tail.expr=generous.target.expr)
    generous_summary <- gRxSummary(generous.results)
    capture.output(print(generous_summary), file="generous_summary.txt")
    
    no.filter.expr <- quote(rep(Inf,ncol(x)))
    no.filter.results <-
        gRxCluster(df3\$chromo,df3\$pos,df3\$grp,15L:30L,nperm=100L,
    	       cutpt.filter.expr=no.filter.expr)
    no_filter_summary <- gRxSummary(no.filter.results)
    capture.output(print(no_filter_summary), file="no_filter_summary.txt")
    
    hard.filter.expr <-
        quote(apply(x,2,quantile, 0.15, na.rm=TRUE))
    hard.filter.results <-
        gRxCluster(df3\$chromo,df3\$pos,df3\$grp,15L:30L,
    	       nperm=100L,
    	       cutpt.filter.expr=hard.filter.expr)
    hard_filter_summary <- gRxSummary(hard.filter.results)
    capture.output(print(hard_filter_summary), file="hard_filter_summary.txt")
    
    # Save results to RDS objects
    saveRDS(null.results, "null_results.rds")
    saveRDS(generous.results, "generous_results.rds")
    saveRDS(no.filter.results, "no_filter_results.rds")
    saveRDS(hard.filter.results, "hard_filter_results.rds")
    
    # Save results to CSV tables
    write.csv(as.data.frame(null.results), "null_results.csv", row.names=FALSE)
    write.csv(as.data.frame(generous.results), "generous_results.csv", row.names=FALSE)
    write.csv(as.data.frame(no.filter.results), "no_filter_results.csv", row.names=FALSE)
    write.csv(as.data.frame(hard.filter.results), "hard_filter_results.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS":',
        paste0('    geneRxCluster: ', as.character(packageVersion('geneRxCluster')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_clustering_analysis.csv versions.yml
    """
}

workflow BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exptData.txt ] ]

    main:
    BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS.out.tables
    plots    = BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS.out.plots
    objects  = BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS.out.objects
    versions = BIOC_GENERXCLUSTER_DIFFERENTIAL_CLUSTERING_ANALYSIS.out.versions
}
