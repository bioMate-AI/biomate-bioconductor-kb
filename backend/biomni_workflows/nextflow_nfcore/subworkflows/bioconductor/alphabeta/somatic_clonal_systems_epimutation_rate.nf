#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AlphaBeta — somatic_clonal_systems_epimutation_rate
// Estimate somatic or clonal epimutation rates and test for selection in trees or clonally propagated species.
// Input: SOMA_nodelist2.fn, SOMA_edgelist2.fn, methylome files
// Container: quay.io/biocontainers/bioconductor-alphabeta:1.24.0--r45hdfd78af_0
// R packages: AlphaBeta, data.table, ggplot2, igraph
// Bioconductor: 3.20 | R: 4.4
// Requires: AlphaBeta, data.table, ggplot2, igraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the pedigree using buildPedigree
//  * 2. [Visualization & Output] Plot the pedigree using plotPedigree
//  * 3. [Core Analysis] Fit neutral (ABneutralSOMA) and selection (ABselectMMSOMA, ABselectUUSOMA) models
//  * 4. [Core Analysis] Perform bootstrap analysis on the best model using BOOTmodel
//  * 5. [Visualization & Output] Plot model fits using ABplot

nextflow.enable.dsl = 2

process BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    treeSamples <- "SOMA_nodelist2.fn"
    treeEdges <- "SOMA_edgelist2.fn"
    out.dir <- getwd()
    
    # 1. Build the pedigree using buildPedigree
    outputTree <- buildPedigree(nodelist = treeSamples,
                            edgelist = treeEdges,
                            cytosine = "CG",
                            posteriorMaxFilter = 0.99)
    
    # Save the pedigree build output
    saveRDS(outputTree, file = "outputTree.rds")
    if (!is.null(outputTree\$Pdata)) {
      write.csv(outputTree\$Pdata, file = "pedigree_Pdata.csv", row.names = FALSE)
    }
    
    # 2. Plot the pedigree using plotPedigree
    plotPedigree(nodelist=treeSamples,
                   edgelist=treeEdges,
                   sampling.design="tree",
                   output.dir=out.dir,
                   plot.width=5,
                   plot.height=5,
                   aspect.ratio=1,
                   vertex.size=8,
                   vertex.label=FALSE,
                   out.pdf="Tree")
    
    # Extract parameters for downstream model fitting
    Tree_p0uu_in <- outputTree\$tmpp0
    pedigree.Tree <- outputTree\$Pdata
    
    # 3. Fit neutral (ABneutralSOMA) and selection (ABselectMMSOMA, ABselectUUSOMA) models
    outputABneutralSOMA <- ABneutralSOMA(
      pedigree.data = pedigree.Tree,
      p0uu = Tree_p0uu_in,
      eqp = Tree_p0uu_in,
      eqp.weight = 0.001,
      Nstarts = 2,
      out.dir = getwd(),
      out.name = "ABneutralSOMA_CG_global_estimates"
    )
    
    outputABselectMMSOMA <- ABselectMMSOMA(
      pedigree.data = pedigree.Tree,
      p0uu = Tree_p0uu_in,
      eqp = Tree_p0uu_in,
      eqp.weight = 0.001,
      Nstarts = 2,
      out.dir = getwd(),
      out.name = "ABselectMMSOMA_CG_global_estimates"
    )
    
    outputABselectUUSOMA <- ABselectUUSOMA(
      pedigree.data = pedigree.Tree,
      p0uu = Tree_p0uu_in,
      eqp = Tree_p0uu_in,
      eqp.weight = 0.001,
      Nstarts = 2,
      out.dir = getwd(),
      out.name = "ABselectUUSOMA_CG_global_estimates"
    )
    
    # Save model estimates to CSV
    if (!is.null(outputABneutralSOMA\$estimates)) {
      write.csv(outputABneutralSOMA\$estimates, "ABneutralSOMA_estimates.csv", row.names = FALSE)
    }
    if (!is.null(outputABselectMMSOMA\$estimates)) {
      write.csv(outputABselectMMSOMA\$estimates, "ABselectMMSOMA_estimates.csv", row.names = FALSE)
    }
    if (!is.null(outputABselectUUSOMA\$estimates)) {
      write.csv(outputABselectUUSOMA\$estimates, "ABselectUUSOMA_estimates.csv", row.names = FALSE)
    }
    
    # 4. Perform bootstrap analysis on the neutral model using BOOTmodel
    inputModelSOMA <- file.path(getwd(), "ABneutralSOMA_CG_global_estimates.Rdata")
    
    Boutput <- BOOTmodel(
      pedigree.data = inputModelSOMA,
      Nboot = 2,
      out.dir = getwd(),
      out.name = "ABneutral_Boot_CG_global_estimates"
    )
    
    # Save bootstrap results
    saveRDS(Boutput, "ABneutral_Boot_output.rds")
    if (!is.null(Boutput\$boot.results)) {
      write.csv(Boutput\$boot.results, "ABneutral_Boot_results.csv", row.names = FALSE)
    }
    if (!is.null(Boutput\$standard.errors)) {
      write.csv(as.data.frame(Boutput\$standard.errors), "ABneutral_Boot_standard_errors.csv")
    }
    
    # 5. Plot model fits using ABplot
    ABfilesoma <- file.path(getwd(), "ABneutralSOMA_CG_global_estimates.Rdata")
    ABplot(pedigree.names=ABfilesoma, output.dir=getwd(), out.name="ABneutralSOMA", plot.height=8, plot.width=11)

    writeLines(c(
        '"BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE":',
        paste0('    AlphaBeta: ', as.character(packageVersion('AlphaBeta')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_somatic_clonal_systems_epimutation_rate.csv versions.yml
    """
}

workflow BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SOMA_nodelist2.fn, SOMA_edgelist2.fn, methylome files ] ]

    main:
    BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE(ch_input)

    emit:
    tables   = BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE.out.tables
    plots    = BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE.out.plots
    objects  = BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE.out.objects
    versions = BIOC_ALPHABETA_SOMATIC_CLONAL_SYSTEMS_EPIMUTATION_RATE.out.versions
}
