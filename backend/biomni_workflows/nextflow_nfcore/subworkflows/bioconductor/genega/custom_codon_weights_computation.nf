#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneGA — custom_codon_weights_computation
// Compute a custom codon adaptation index (CAI) weight table (w-table) from a set of highly expressed genes.
// Input: EGFP.fasta
// Container: quay.io/biocontainers/bioconductor-genega:1.60.0--r45hdfd78af_0
// R packages: GeneGA, hash, seqinr
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneGA, hash, seqinr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the highly expressed gene sequences
//  * 2. [Core Analysis] Calculate Relative Synonymous Codon Usage (RSCU)
//  * 3. [Core Analysis] Compute the w-value (relative adaptiveness of each codon) by normalizing RSCU values against the maximum RSCU for each amino acid

nextflow.enable.dsl = 2

process BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("GeneGA", "hash", "seqinr")
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
    library(GeneGA)
    library(seqinr)
    library(hash)
    
    # Define input file (must be in the working directory as specified)
    seqfile <- "EGFP.fasta"
    
    # Check if input file exists
    if (!file.exists(seqfile)) {
      stop(paste("Required input file missing:", seqfile))
    }
    
    # 1. Read the highly expressed gene sequences
    aa = read.fasta(seqfile)
    
    # 2. Calculate Relative Synonymous Codon Usage (RSCU)
    rscu = uco(unlist(aa), index="rscu")
    
    # 3. Compute the w-value (relative adaptiveness of each codon)
    w_value = rscu
    names(w_value) = names(rscu)
    names = sapply(names(rscu), function(x) translate(s2c(x)))
    amino = hash()
    for(i in unique(names)){
    	amino[[i]] = max(rscu[which(names==i)])
    }
    for(i in 1:length(names)){
    	w_value[i] = rscu[[names(rscu)[i]]]/amino[[translate(s2c(names(rscu)[i]))]]
    }
    
    # Export the computed codon weights to output files
    w_df <- data.frame(
      Codon = names(w_value),
      AminoAcid = names,
      W_Value = as.numeric(w_value),
      stringsAsFactors = FALSE
    )
    
    write.csv(w_df, file = "custom_codon_weights.csv", row.names = FALSE)
    saveRDS(w_value, file = "custom_codon_weights.rds")
    
    cat("Custom codon weights computation completed successfully. Outputs saved to 'custom_codon_weights.csv' and 'custom_codon_weights.rds'.\n")

    writeLines(c(
        '"BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION":',
        paste0('    GeneGA: ', as.character(packageVersion('GeneGA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_codon_weights_computation.csv versions.yml
    """
}

workflow BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ EGFP.fasta ] ]

    main:
    BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION(ch_input)

    emit:
    tables   = BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION.out.tables
    plots    = BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION.out.plots
    objects  = BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION.out.objects
    versions = BIOC_GENEGA_CUSTOM_CODON_WEIGHTS_COMPUTATION.out.versions
}
