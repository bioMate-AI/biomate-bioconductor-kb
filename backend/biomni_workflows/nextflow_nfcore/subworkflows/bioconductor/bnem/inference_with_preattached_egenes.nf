#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bnem — inference_with_preattached_egenes
// Infer pathway logic while fixing or restricting the attachment of downstream E-genes to specific upstream S-genes.
// Input: PKN, fc, CNOlist, model
// Container: quay.io/biocontainers/bioconductor-bnem:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CellNOptR, bnem, mnem
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Map E-genes to their corresponding S-genes based on prior
//  * 2. [Visualization & Output] Initialize the network state
//  * 3. [Visualization & Output] Run B-NEM optimization with the egenes parameter
//  * 4. [Visualization & Output] Calculate network residuals to evaluate E-gene fit

nextflow.enable.dsl = 2

process BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(bnem)
    library(mnem)
    library(CellNOptR)
    
    # Read user input files from the working directory
    PKN <- readRDS("PKN.rds")
    fc <- readRDS("fc.rds")
    CNOlist <- readRDS("CNOlist.rds")
    model <- readRDS("model.rds")
    
    # Define auxiliary variables required by the documented code
    expression <- NULL
    parallel <- NULL
    
    # --- Map E-genes to their corresponding S-genes based on prior ---
    egenes <- list()
    for (i in PKN\$namesSpecies) {
        egenes[[i]] <- rownames(fc)[grep(i, rownames(fc))]
    }
    
    # --- Initialize the network state ---
    initBstring <- reduceGraph(rep(0, length(model\$reacID)), model, CNOlist)
    
    # --- Run B-NEM optimization with the egenes parameter ---
    greedy2b <- bnem(search = "greedy",
                     CNOlist=CNOlist,
                     fc=fc,
                     expression=expression,
                     egenes=egenes,
                     model=model,
                     parallel=parallel,
                     initBstring=initBstring,
                     draw = FALSE,
                     verbose = FALSE,
                     maxSteps = Inf,
                     method = "cosine"
                     )
    resString3 <- greedy2b\$bString
    
    # --- Calculate network residuals to evaluate E-gene fit ---
    residuals <- findResiduals(resString3, CNOlist, model, fc, verbose = FALSE)
    
    # Save results to RDS files
    saveRDS(greedy2b, "greedy2b.rds")
    saveRDS(resString3, "resString3.rds")
    saveRDS(residuals, "residuals.rds")
    
    # Export visualizations to PDF
    pdf("network_and_residuals.pdf", width = 10, height = 8)
    
    # Plot the optimized network structure
    tryCatch({
        children <- unique(gsub(".*=|!", "", PKN\$reacID))
        stimuli <- unique(gsub("=.*|!", "", PKN\$reacID))
        stimuli <- stimuli[which(!(stimuli %in% children))]
        mnem::plotDnf(model\$reacID[as.logical(resString3)], main = "Greedy Optimum Network", stimuli = stimuli)
    }, error = function(e) {
        message("Could not plot network: ", e\$message)
    })
    
    # Plot the residuals matrix (verbose = TRUE triggers plotting in findResiduals)
    tryCatch({
        findResiduals(resString3, CNOlist, model, fc, verbose = TRUE)
    }, error = function(e) {
        message("Could not plot residuals: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES":',
        paste0('    bnem: ', as.character(packageVersion('bnem')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inference_with_preattached_egenes.csv versions.yml
    """
}

workflow BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PKN, fc, CNOlist, model ] ]

    main:
    BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES(ch_input)

    emit:
    tables   = BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES.out.tables
    plots    = BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES.out.plots
    objects  = BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES.out.objects
    versions = BIOC_BNEM_INFERENCE_WITH_PREATTACHED_EGENES.out.versions
}
