#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trigger — causal_network_inference
// Reconstruct causal transcriptional regulatory networks from matched genotype and gene expression data using eQTL-directed graphical models.
// Input: genotypes.txt, expression.txt, marker_positions.txt, gene_positions.txt
// Container: quay.io/biocontainers/bioconductor-trigger:1.52.0--r44h3df3fcb_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: trigger
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the trigger object using trigger.build
//  * 2. [Core Analysis] Compute local linkage (eQTLs) using trigger.loclink
//  * 3. [Core Analysis] Estimate the posterior probabilities of causal regulation using trigger.prob
//  * 4. [Core Analysis] Reconstruct the causal network using trigger.net
//  * 5. [Visualization & Output] Export the network using trigger.export

nextflow.enable.dsl = 2

process BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE {
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
        
        # Load the required Bioconductor package
        library(trigger)
        
        # Read the user input files from the working directory
        # genotypes.txt: matrix of marker genotypes (rows = markers, columns = individuals)
        gact <- as.matrix(read.table("genotypes.txt", header = TRUE, row.names = 1, check.names = FALSE))
        
        # expression.txt: matrix of gene expression levels (rows = genes, columns = individuals)
        gexp <- as.matrix(read.table("expression.txt", header = TRUE, row.names = 1, check.names = FALSE))
        
        # marker_positions.txt: data frame containing marker physical positions (name, chromosome, physical position)
        gpos <- read.table("marker_positions.txt", header = TRUE, stringsAsFactors = FALSE)
        
        # gene_positions.txt: data frame containing gene physical positions (name, chromosome, start, end)
        ppos <- read.table("gene_positions.txt", header = TRUE, stringsAsFactors = FALSE)
        
        # Stage 1: Build the trigger object
        trig <- trigger.build(marker = gact, exp = gexp, marker.pos = gpos, exp.pos = ppos)
        
        # Stage 2: Compute local linkage (eQTLs)
        trig.loc <- trigger.loclink(trig, window.size = 100000)
        
        # Stage 3: Estimate the posterior probabilities of causal regulation
        trig.prob <- trigger.prob(trig.loc, logratio = TRUE)
        
        # Stage 4: Reconstruct the causal network
        trig.net <- trigger.net(trig.prob, prob.cutoff = 0.9)
        
        # Stage 5: Export the network to the specified file
        trigger.export(trig.net, file = "causal_network.txt")
        
        # Save intermediate and final R objects for downstream analysis
        saveRDS(trig, "trigger_build.rds")
        saveRDS(trig.loc, "trigger_loclink.rds")
        saveRDS(trig.prob, "trigger_prob.rds")
        saveRDS(trig.net, "trigger_net.rds")

    writeLines(c(
        '"BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE":',
        paste0('    trigger: ', as.character(packageVersion('trigger')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_causal_network_inference.csv versions.yml
    """
}

workflow BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotypes.txt, expression.txt, marker_positions.txt, gene_positions.txt ] ]

    main:
    BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE.out.tables
    plots    = BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE.out.plots
    objects  = BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE.out.objects
    versions = BIOC_TRIGGER_CAUSAL_NETWORK_INFERENCE.out.versions
}
