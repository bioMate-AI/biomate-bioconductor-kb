#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alphabeta — somatic_epimutation_analysis
// Estimate somatic epimutation rates and test for selection in clonal, asexual, or somatic systems (such as trees).
// Input: SOMA_nodelist.fn, SOMA_edgelist.fn, somatic_methylome_files
// Container: quay.io/biocontainers/bioconductor-alphabeta:1.24.0--r45hdfd78af_0
// R packages: AlphaBeta, data.table, ggplot2, igraph
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-alphabeta:1.24.0--r45hdfd78af_0"

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
    .bm_deps <- c("AlphaBeta", "data.table", "ggplot2", "igraph")
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
    library(AlphaBeta)
    library(data.table)
    library(igraph)
    library(ggplot2)
    
    # Define input file paths from the working directory
    treeSamples <- "SOMA_nodelist.fn"
    treeEdges <- "SOMA_edgelist.fn"
    out.dir <- getwd()
    
    # --- Build the somatic pedigree and calculate pairwise ---
    outputTree <- buildPedigree(
      nodelist = treeSamples,
      edgelist = treeEdges,
      cytosine = "CG",
      posteriorMaxFilter = 0.99
    )
    
    # Save the pedigree output object
    saveRDS(outputTree, file = "outputTree.rds")
    write.csv(outputTree\$Pdata, file = "pedigree_divergence_values.csv", row.names = FALSE)
    
    # --- Generate diagnostic somatic pedigree plots ---
    plotPedigree(
      nodelist = treeSamples,
      edgelist = treeEdges,
      sampling.design = "tree",
      output.dir = out.dir,
      plot.width = 5,
      plot.height = 5,
      aspect.ratio = 1,
      vertex.size = 8,
      vertex.label = FALSE,
      out.pdf = "Tree"
    )
    
    # Extract parameters for model fitting
    Tree_p0uu_in <- outputTree\$tmpp0
    pedigree.Tree <- outputTree\$Pdata
    
    # --- Fit the neutral somatic epimutation model ---
    outputABneutralSOMA <- ABneutralSOMA(
      pedigree.data = pedigree.Tree,
      p0uu = Tree_p0uu_in,
      eqp = Tree_p0uu_in,
      eqp.weight = 0.001,
      Nstarts = 2,
      out.dir = getwd(),
      out.name = "ABneutralSOMA_CG_global_estimates"
    )
    
    # Save neutral model results
    saveRDS(outputABneutralSOMA, file = "outputABneutralSOMA.rds")
    write.csv(outputABneutralSOMA\$estimates, file = "ABneutralSOMA_estimates.csv", row.names = FALSE)
    
    # --- Fit somatic selection models ---
    outputABselectMMSOMA <- ABselectMMSOMA(
      pedigree.data = pedigree.Tree,
      p0uu = Tree_p0uu_in,
      eqp = Tree_p0uu_in,
      eqp.weight = 0.001,
      Nstarts = 2,
      out.dir = getwd(),
      out.name = "ABselectMMSOMA_CG_global_estimates"
    )
    
    saveRDS(outputABselectMMSOMA, file = "outputABselectMMSOMA.rds")
    write.csv(outputABselectMMSOMA\$estimates, file = "ABselectMMSOMA_estimates.csv", row.names = FALSE)
    
    outputABselectUUSOMA <- ABselectUUSOMA(
      pedigree.data = pedigree.Tree,
      p0uu = Tree_p0uu_in,
      eqp = Tree_p0uu_in,
      eqp.weight = 0.001,
      Nstarts = 2,
      out.dir = getwd(),
      out.name = "ABselectUUSOMA_CG_global_estimates"
    )
    
    saveRDS(outputABselectUUSOMA, file = "outputABselectUUSOMA.rds")
    write.csv(outputABselectUUSOMA\$estimates, file = "ABselectUUSOMA_estimates.csv", row.names = FALSE)
    
    # --- Perform bootstrap analysis on the somatic model ---
    inputModelSOMA <- file.path(getwd(), "ABneutralSOMA_CG_global_estimates.Rdata")
    
    Boutput <- BOOTmodel(
      pedigree.data = inputModelSOMA,
      Nboot = 2,
      out.dir = getwd(),
      out.name = "ABneutral_Boot_CG_global_estimates"
    )
    
    # Save bootstrap results
    saveRDS(Boutput, file = "Boutput.rds")
    write.csv(as.data.frame(Boutput\$standard.errors), file = "Boutput_standard_errors.csv")
    
    # --- Plot the final somatic model fit ---
    ABfilesoma <- file.path(getwd(), "ABneutralSOMA_CG_global_estimates.Rdata")
    
    ABplot(
      pedigree.names = ABfilesoma,
      output.dir = getwd(),
      out.name = "ABneutralSOMA",
      plot.height = 8,
      plot.width = 11
    )

    writeLines(c(
        '"BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS":',
        paste0('        alphabeta: ', as.character(packageVersion("alphabeta")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_somatic_epimutation_analysis.csv versions.yml
    """
}

workflow BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SOMA_nodelist.fn, SOMA_edgelist.fn, somatic_methylome_files ] ]

    main:
    BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS.out.tables
    plots    = BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS.out.plots
    objects  = BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS.out.objects
    versions = BIOC_ALPHABETA_SOMATIC_EPIMUTATION_ANALYSIS.out.versions
}
