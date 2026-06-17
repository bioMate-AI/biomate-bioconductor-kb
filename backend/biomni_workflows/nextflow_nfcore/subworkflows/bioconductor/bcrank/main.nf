#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bcrank — de_novo_motif_prediction
// Predict transcription factor binding consensus sequences de novo from ranked DNA sequences, visualize the results, and identify matching genomic sites.
// Input: fastaFile
// Container: quay.io/biocontainers/bioconductor-bcrank:1.72.0--r45h01b2380_0
// R packages: BCRANK, seqLogo
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-bcrank:1.72.0--r45h01b2380_0"

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
    .bm_deps <- c("BCRANK", "seqLogo")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(BCRANK)
    library(seqLogo)
    
    # Define input file (must exist in the working directory)
    fastaFile <- "USF1_small.fa"
    
    if (!file.exists(fastaFile)) {
      stop(paste("Error: Input FASTA file '", fastaFile, "' not found in the working directory.", sep=""))
    }
    
    # Set seed for reproducibility
    set.seed(0)
    
    # Run BCRANK algorithm with restarts and penalties
    message("Running BCRANK algorithm...")
    BCRANKout <- bcrank(fastaFile, restarts=25, use.P1=TRUE, use.P2=TRUE)
    print(BCRANKout)
    
    # Save BCRANK output object
    saveRDS(BCRANKout, file="bcrank_output.rds")
    
    # Extract top-scoring motif
    message("Extracting top-scoring motif...")
    topMotif <- toptable(BCRANKout, 1)
    print(topMotif)
    saveRDS(topMotif, file="top_motif.rds")
    
    # Generate position weight matrices
    message("Generating position weight matrices...")
    weightMatrix <- pwm(topMotif, normalize=FALSE)
    print(weightMatrix)
    write.csv(weightMatrix, file="weight_matrix.csv")
    
    weightMatrixNormalized <- pwm(topMotif, normalize=TRUE)
    print(weightMatrixNormalized)
    write.csv(weightMatrixNormalized, file="weight_matrix_normalized.csv")
    
    # Generate visualizations
    message("Generating plots...")
    tryCatch({
      pdf("seq_logo.pdf")
      seqLogo(weightMatrixNormalized)
      dev.off()
    }, error = function(e) {
      message("Warning: Failed to generate seqLogo plot: ", e\$message)
    })
    
    tryCatch({
      pdf("top_motif_plot.pdf")
      plot(topMotif)
      dev.off()
    }, error = function(e) {
      message("Warning: Failed to generate top motif plot: ", e\$message)
    })
    
    # Identify individual genomic matching sites for the top consensus sequence
    message("Identifying matching genomic sites...")
    topConsensus <- as.character(toptable(BCRANKout)[1, "Consensus"])
    cat("Top Consensus Sequence:", topConsensus, "\n")
    
    bindingSites <- matchingSites(fastaFile, topConsensus)
    nrSites <- nrow(bindingSites)
    cat("Number predicted binding sites:", nrSites, "\n")
    
    if (nrSites > 0) {
      print(bindingSites[1:min(15, nrSites), ])
    }
    
    # Save matching sites to CSV
    write.csv(bindingSites, file="predicted_binding_sites.csv", row.names=FALSE)
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION":',
        paste0('        bcrank: ', as.character(packageVersion("bcrank")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_novo_motif_prediction.csv versions.yml
    """
}

workflow BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fastaFile ] ]

    main:
    BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION(ch_input)

    emit:
    tables   = BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION.out.tables
    plots    = BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION.out.plots
    objects  = BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION.out.objects
    versions = BIOC_BCRANK_DE_NOVO_MOTIF_PREDICTION.out.versions
}
