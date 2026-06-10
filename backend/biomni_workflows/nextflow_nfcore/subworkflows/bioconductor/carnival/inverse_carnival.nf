#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CARNIVAL — inverse_carnival
// Contextualize a signaling network when the upstream perturbation targets are unknown.
// Input: toy_measurements_ex2.RData, toy_network_ex2.RData
// Container: quay.io/biocontainers/bioconductor-carnival:2.20.0--r45hdfd78af_0
// R packages: CARNIVAL
// Bioconductor: 3.20 | R: 4.4
// Requires: CARNIVAL
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load measurements and prior knowledge network
//  * 2. [Core Analysis] Format prior knowledge network columns to 'source', 'interaction', and 'target'
//  * 3. [Core Analysis] Initialize solver options
//  * 4. [Core Analysis] Run inverse pipeline using runInverseCarnival

nextflow.enable.dsl = 2

process BIOC_CARNIVAL_INVERSE_CARNIVAL {
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
    .bm_deps <- c("CARNIVAL")
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
    library(CARNIVAL)
    
    # 1. Load measurements and prior knowledge network from the working directory
    load(file = "toy_measurements_ex2.RData")
    load(file = "toy_network_ex2.RData")
    
    # 2. Initialize solver options
    carnivalOptions <- defaultLpSolveCarnivalOptions()
    
    # Output dir
    dir.create("ToyExample2", showWarnings = FALSE)
    carnivalOptions\$outputFolder <- "ToyExample2"
    
    # 3. Format prior knowledge network columns to 'source', 'interaction', and 'target'
    toy_network_ex2 <- as.data.frame(toy_network_ex2)
    colnames(toy_network_ex2) <- c("source", "interaction", "target")
    
    # 4. Run inverse pipeline using runInverseCarnival
    inverseCarnivalResults <- runInverseCarnival( measurements = toy_measurements_ex2, 
                                                  priorKnowledgeNetwork = toy_network_ex2, 
                                                  carnivalOptions = carnivalOptions)
    
    # Save meaningful results to output files
    saveRDS(inverseCarnivalResults, file = "ToyExample2/inverseCarnivalResults.Rds")
    
    if (!is.null(inverseCarnivalResults\$weightedSIF)) {
      write.csv(as.data.frame(inverseCarnivalResults\$weightedSIF), 
                file = "ToyExample2/weightedSIF.csv", 
                row.names = FALSE)
    }
    
    if (!is.null(inverseCarnivalResults\$nodesAttributes)) {
      write.csv(as.data.frame(inverseCarnivalResults\$nodesAttributes), 
                file = "ToyExample2/nodesAttributes.csv", 
                row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_CARNIVAL_INVERSE_CARNIVAL":',
        paste0('    CARNIVAL: ', as.character(packageVersion('CARNIVAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inverse_carnival.csv versions.yml
    """
}

workflow BIOC_CARNIVAL_INVERSE_CARNIVAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ toy_measurements_ex2.RData, toy_network_ex2.RData ] ]

    main:
    BIOC_CARNIVAL_INVERSE_CARNIVAL(ch_input)

    emit:
    tables   = BIOC_CARNIVAL_INVERSE_CARNIVAL.out.tables
    plots    = BIOC_CARNIVAL_INVERSE_CARNIVAL.out.plots
    objects  = BIOC_CARNIVAL_INVERSE_CARNIVAL.out.objects
    versions = BIOC_CARNIVAL_INVERSE_CARNIVAL.out.versions
}
