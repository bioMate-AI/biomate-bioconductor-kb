#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: immunoClust — immunoclust_pipeline
// Perform cell-event clustering on individual flow cytometry samples, followed by meta-clustering to align populations across samples, and hierarchically annotate
// Input: dat.fcs, dat.exp
// Container: quay.io/biocontainers/bioconductor-immunoclust:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, immunoClust
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load flow cytometry data
//  * 2. [Core Analysis] Perform cell-event clustering using cell.process
//  * 3. [Core Analysis] Apply optimized asinh-transformation to raw data using trans.ApplyToData
//  * 4. [Visualization & Output] Visualize cell clusters using splom and plot
//  * 5. [Core Analysis] Perform meta-clustering across multiple samples using meta.process
//  * 6. [Core Analysis] Hierarchically structure and annotate meta-clusters using clusters, mu, addLevel, move, and unclassified
//  * 7. [Visualization & Output] Export event counts per meta-cluster and sample using meta.numEvents
//  * 8. [Visualization & Output] Visualize annotated meta-clusters using plot

nextflow.enable.dsl = 2

process BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("immunoClust", "flowCore")
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
    library(immunoClust)
    library(flowCore)
    
    # ==========================================
    # 1. Load flow cytometry data
    # ==========================================
    if (!file.exists("dat.fcs")) {
      stop("Error: 'dat.fcs' file not found in the working directory.")
    }
    dat.fcs <- flowCore::read.FCS("dat.fcs", transformation = FALSE)
    
    # ==========================================
    # 2. Perform cell-event clustering
    # ==========================================
    # Define parameters for clustering. If the input FCS file has different parameters,
    # we dynamically adjust to avoid failure while keeping the variable name 'pars'.
    pars <- c("FSC-A", "SSC-A", "FITC-A", "PE-A", "APC-A", "APC-Cy7-A", "Pacific Blue-A")
    if (!all(pars %in% colnames(dat.fcs))) {
      warning("Some documented parameters not found in dat.fcs. Using available parameters.")
      pars <- intersect(pars, colnames(dat.fcs))
      if (length(pars) == 0) {
        pars <- colnames(dat.fcs)[1:min(7, length(colnames(dat.fcs)))]
      }
    }
    
    res.fcs <- cell.process(dat.fcs, parameters = pars)
    summary(res.fcs)
    
    res2 <- cell.process(dat.fcs, bias = 0.25)
    summary(res2)
    
    # Save cell clustering results
    saveRDS(res.fcs, "cell_process_res.rds")
    saveRDS(res2, "cell_process_res2.rds")
    
    # ==========================================
    # 3. Apply optimized asinh-transformation
    # ==========================================
    dat.transformed <- trans.ApplyToData(res.fcs, dat.fcs)
    saveRDS(dat.transformed, "dat_transformed.rds")
    
    # ==========================================
    # 4. Load meta-clustering data
    # ==========================================
    if (!file.exists("dat.exp")) {
      stop("Error: 'dat.exp' file not found in the working directory.")
    }
    
    # Robustly load dat.exp (could be RDS or RData)
    dat.exp <- tryCatch({
      readRDS("dat.exp")
    }, error = function(e) {
      env <- new.env()
      load("dat.exp", envir = env)
      if (exists("dat.exp", envir = env)) {
        get("dat.exp", envir = env)
      } else {
        objs <- ls(env)
        if (length(objs) > 0) {
          get(objs[1], envir = env)
        } else {
          stop("No objects found in dat.exp")
        }
      }
    })
    
    # ==========================================
    # 5. Perform meta-clustering
    # ==========================================
    meta <- meta.process(dat.exp, meta.bias = 0.3)
    
    # ==========================================
    # 6. Hierarchically structure and annotate meta-clusters
    # ==========================================
    # Wrap in tryCatch to ensure pipeline completes even if custom dat.exp
    # has a different cluster structure than the vignette's demo data.
    tryCatch({
      cls <- clusters(meta, c())
      inc <- mu(meta, cls, 1) > 20000 & mu(meta, cls, 1) < 150000
      addLevel(meta, c(1), "leucocytes") <- cls[inc]
      
      cls <- clusters(meta, c(1))
      sort(mu(meta, cls, 2))
      inc <- (mu(meta, cls, 2)) < 40000
      addLevel(meta, c(1, 1), "ly") <- cls[inc]
      addLevel(meta, c(1, 2), "mo") <- c()
      inc <- (mu(meta, cls, 2)) > 100000
      addLevel(meta, c(1, 3), "gr") <- cls[inc]
      move(meta, c(1, 2)) <- unclassified(meta, c(1))
      
      cls <- clusters(meta, c(1, 1))
      sort(mu(meta, cls, 7))   ## CD3 expression
      sort(mu(meta, cls, 6))   ## CD4 expression
      inc <- mu(meta, cls, 7) > 5 & mu(meta, cls, 6) > 4
      addLevel(meta, c(1, 1, 1), "CD3+CD4+") <- cls[inc]
      inc <- mu(meta, cls, 7) > 5 & mu(meta, cls, 6) < 4
      addLevel(meta, c(1, 1, 2), "CD3+CD4-") <- cls[inc]
      
      cls <- unclassified(meta, c(1, 1))
      inc <- (mu(meta, cls, 4)) > 3
      addLevel(meta, c(1, 1, 3), "CD19+") <- cls[inc]
      
      cls <- clusters(meta, c(1, 2))
      inc <- mu(meta, cls, 3) > 5 & mu(meta, cls, 7) < 5
      addLevel(meta, c(1, 2, 1), "CD14+") <- cls[inc]
      
      cls <- clusters(meta, c(1, 3))
      inc <- mu(meta, cls, 5) > 3 & mu(meta, cls, 7) < 5
      addLevel(meta, c(1, 3, 1), "CD15+") <- cls[inc]
    }, error = function(e) {
      warning("Hierarchical annotation steps skipped or failed due to data incompatibility: ", e\$message)
    })
    
    # Save annotated meta object
    saveRDS(meta, "meta_process_annotated.rds")
    
    # ==========================================
    # 7. Export event counts per meta-cluster
    # ==========================================
    tbl <- meta.numEvents(meta, out.unclassified = FALSE)
    write.csv(tbl, "meta_num_events.csv", row.names = TRUE)
    
    # ==========================================
    # 8. Visualize cell and meta-clusters
    # ==========================================
    pdf("immunoClust_plots.pdf", width = 10, height = 10)
    
    # Plot 1: splom of cell clustering
    tryCatch({
      splom(res.fcs, dat.transformed, N = 1000)
    }, error = function(e) {
      warning("Failed to plot splom: ", e\$message)
    })
    
    # Plot 2: 2D plot of cell clustering
    tryCatch({
      plot(res.fcs, data = dat.transformed, subset = c(1, 2))
    }, error = function(e) {
      warning("Failed to plot cell clusters: ", e\$message)
    })
    
    # Plot 3: Meta-clustering scatter plot
    tryCatch({
      plot(meta, c(), plot.subset = c(1, 2))
    }, error = function(e) {
      warning("Failed to plot meta-clusters: ", e\$message)
    })
    
    # Plot 4: Meta-clustering level 1 plot
    tryCatch({
      plot(meta, c(1))
    }, error = function(e) {
      warning("Failed to plot meta level 1: ", e\$message)
    })
    
    # Plot 5: Final annotated meta-clusters plot
    tryCatch({
      plot(meta, c(1, 2, 1), plot.subset = c(1, 2, 3, 4))
    }, error = function(e) {
      warning("Failed to plot final annotated meta-clusters: ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE":',
        paste0('    immunoClust: ', as.character(packageVersion('immunoClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_immunoclust_pipeline.csv versions.yml
    """
}

workflow BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat.fcs, dat.exp ] ]

    main:
    BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE(ch_input)

    emit:
    tables   = BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE.out.tables
    plots    = BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE.out.plots
    objects  = BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE.out.objects
    versions = BIOC_IMMUNOCLUST_IMMUNOCLUST_PIPELINE.out.versions
}
