#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowCore — gatingset_hierarchical_analysis
// Perform hierarchical gating and population analysis using GatingSet, GatingHierarchy, and automated gating functions.
// Input: fcsfiles.FCS, comp
// Container: quay.io/biocontainers/bioconductor-flowcore:2.22.1--r45ha27e39d_0
// R packages: flowCore, flowWorkspace
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowWorkspace
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a GatingSet from a flowSet
//  * 2. [Core Analysis] Apply spectral compensation
//  * 3. [Core Analysis] Transform channels using biexponential or logicle scales
//  * 4. [Core Analysis] Add gates hierarchically to the GatingSet
//  * 5. [Core Analysis] Recompute the gating tree
//  * 6. [Core Analysis] Extract population statistics and subset data

nextflow.enable.dsl = 2

process BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS {
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
    .bm_deps <- c("flowCore", "flowWorkspace")
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
                    library(flowCore)
                    library(flowWorkspace)
                    
                    # 1. Read User Inputs
                    # Read the raw FCS file
                    fr <- read.FCS("fcsfiles.FCS", transformation = FALSE)
                    fs <- flowSet(fr)
                    
                    # Read the compensation matrix object
                    comp <- readRDS("comp")
                    if (is.matrix(comp)) {
                      comp <- compensation(comp)
                    }
                    
                    # 2. Execute GatingSet Hierarchical Analysis Workflow
                    gs <- GatingSet(fs)
                    comp
                    gs <- compensate(gs, comp)
                    fs_comp <- gs_pop_get_data(gs)
                    biexpTrans <- flowJo_biexp_trans(channelRange=4096, maxValue=262144
                                              , pos=4.5,neg=0, widthBasis=-10)
                    chnls <- parameters(comp)
                    tf <- transformerList(chnls, biexpTrans)
                    gs <- transform(gs, tf)
                    
                    fr_trans <- gs_pop_get_data(gs)[[1]]
                    cols <- colnames(fr_trans)
                    c1 <- cols[1]
                    c2 <- cols[min(2, length(cols))]
                    c3 <- cols[min(3, length(cols))]
                    c4 <- cols[min(4, length(cols))]
                    c5 <- cols[min(5, length(cols))]
                    
                    rg1_args <- list(c(min(exprs(fr_trans)[, c1], na.rm = TRUE), Inf))
                    names(rg1_args) <- c1
                    rg1_args\$filterId <- "NonDebris"
                    rg1 <- do.call(rectangleGate, rg1_args)
                    gs_pop_add(gs, rg1, parent = "root")
                    gs_pop_recompute(gs)
                    stats_nondebris <- gh_pop_get_stats(gs[[1]], "NonDebris")
                    
                    c1_min <- min(exprs(fr_trans)[, c1], na.rm = TRUE)
                    c1_max <- max(exprs(fr_trans)[, c1], na.rm = TRUE)
                    c2_min <- min(exprs(fr_trans)[, c2], na.rm = TRUE)
                    c2_max <- max(exprs(fr_trans)[, c2], na.rm = TRUE)
                    mat <- matrix(c(c1_min, c1_max, c1_max, c1_min, c1_min,
                                    c2_min, c2_min, c2_max, c2_max, c2_min), nrow = 5)
                    colnames(mat) <- c(c1, c2)
                    pg <- polygonGate(.gate = mat)
                    gs_pop_add(gs, pg, parent = "NonDebris", name = "singlets")
                    
                    rg2_args <- list(c(min(exprs(fr_trans)[, c3], na.rm = TRUE), Inf))
                    names(rg2_args) <- c3
                    rg2 <- do.call(rectangleGate, rg2_args)
                    gs_pop_add(gs, rg2, parent = "singlets", name = "CD3")
                    
                    qg_args <- list(mean(exprs(fr_trans)[, c4], na.rm = TRUE), mean(exprs(fr_trans)[, c5], na.rm = TRUE))
                    names(qg_args) <- c(c4, c5)
                    qg <- do.call(quadGate, qg_args)
                    gs_pop_add(gs, qg, parent="CD3", name = c("CD8", "DPT", "CD4", "DNT"))
                    gs_pop_recompute(gs, "singlets")
                    fs_nonDebris <- gs_pop_get_data(gs, "NonDebris")
                    counts <- gs_pop_get_count(gs)
                    
                    # 3. Save Outputs
                    write.csv(as.data.frame(stats_nondebris), "stats_nondebris.csv", row.names = TRUE)
                    write.csv(counts, "pop_counts.csv", row.names = TRUE)
                    
                    # Save the non-debris flowSet
                    write.flowSet(fs_nonDebris, outdir = "fs_nonDebris_output")
                    
                    # Save the final GatingSet
                    save_gs(gs, path = "gs_output")

    writeLines(c(
        '"BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS":',
        paste0('    flowCore: ', as.character(packageVersion('flowCore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gatingset_hierarchical_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fcsfiles.FCS, comp ] ]

    main:
    BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS.out.tables
    plots    = BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS.out.plots
    objects  = BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS.out.objects
    versions = BIOC_FLOWCORE_GATINGSET_HIERARCHICAL_ANALYSIS.out.versions
}
