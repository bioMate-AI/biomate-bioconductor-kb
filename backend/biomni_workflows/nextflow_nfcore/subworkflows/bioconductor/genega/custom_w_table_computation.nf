#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genega — custom_w_table_computation
// Compute a custom codon relative adaptiveness (w) table from highly expressed genes of a specific species or tissue.
// Input: EGFP.fasta
// Container: quay.io/biocontainers/bioconductor-genega:1.60.0--r45hdfd78af_0
// R packages: GeneGA, hash, seqinr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genega:1.60.0--r45hdfd78af_0"

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
    
    # Define the input file (must be in the working directory)
    seqfile <- "EGFP.fasta"
    
    if (!file.exists(seqfile)) {
      stop("Error: Input file 'EGFP.fasta' not found in the working directory.")
    }
    
    # 1. Read the highly expressed gene sequences
    aa=read.fasta(seqfile)
    
    # 2. Calculate the Relative Synonymous Codon Usage (RSCU)
    rscu=uco(unlist(aa), index="rscu")
    
    # 3. Compute the relative adaptiveness (w) values by normalizing RSCU against the maximum RSCU for each amino acid
    w_value=rscu # w_value is the w table we need computing
    names(w_value)=names(rscu)
    names=sapply(names(rscu), function(x) translate(s2c(x)))
    amino=hash()
    for(i in unique(names)){
    	amino[[i]]=max(rscu[which(names==i)])
    }
    for(i in 1:length(names)){
    	w_value[i]=rscu[[names(rscu)[i]]]/amino[[translate(s2c(names(rscu)[i]))]]
    }
    
    # Save the computed w table to output files
    w_df <- data.frame(
      Codon = names(w_value),
      w = as.numeric(w_value),
      stringsAsFactors = FALSE
    )
    
    write.csv(w_df, "custom_w_table.csv", row.names = FALSE)
    saveRDS(w_value, "custom_w_table.rds")
    
    cat("Computation complete. Outputs saved to 'custom_w_table.csv' and 'custom_w_table.rds'.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION":
        genega: \$(Rscript -e 'cat(as.character(packageVersion("genega")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_w_table_computation.csv versions.yml
    """
}

workflow BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ EGFP.fasta ] ]

    main:
    BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION(ch_input)

    emit:
    tables   = BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION.out.tables
    plots    = BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION.out.plots
    objects  = BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION.out.objects
    versions = BIOC_GENEGA_CUSTOM_W_TABLE_COMPUTATION.out.versions
}
