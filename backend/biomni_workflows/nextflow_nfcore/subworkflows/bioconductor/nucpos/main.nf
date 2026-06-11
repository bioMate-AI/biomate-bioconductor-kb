#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nuCpos — nucleosome_affinity_prediction
// Calculate whole and local histone binding affinity (HBA) scores for a 147-bp DNA sequence to predict nucleosome positioning.
// Input: sequence.RData, sequence_DNAString.RData
// Container: quay.io/biocontainers/bioconductor-nucpos:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, nuCpos
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the nuCpos package and input sequence
//  * 2. [Core Analysis] Calculate the whole nucleosomal HBA score using the HBA function
//  * 3. [Core Analysis] Calculate local HBA scores for 13 subnucleosomal segments using the localHBA function
//  * 4. [Visualization & Output] Visualize local HBA scores using a barplot

nextflow.enable.dsl = 2

process BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("nuCpos", "Biostrings")
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
    
    # 1. Load required packages
    library(nuCpos)
    library(Biostrings)
    
    # 2. Load input sequences from the working directory
    # We load them into separate environments to robustly retrieve the objects 
    # regardless of their internal variable names, then assign them to the 
    # exact variable names used in the documented code.
    env_char <- new.env()
    load("sequence.RData", envir = env_char)
    inseq <- env_char[[names(env_char)[1]]]
    
    env_ds <- new.env()
    load("sequence_DNAString.RData", envir = env_ds)
    INSEQ <- env_ds[[names(env_ds)[1]]]
    
    # 3. Calculate whole nucleosomal HBA scores
    hba_char <- HBA(inseq = inseq, species = "sc")
    hba_ds <- HBA(inseq = INSEQ, species = "sc")
    
    # Save whole HBA scores to a CSV file
    hba_results <- data.frame(
      Input_Type = c("character", "DNAString"),
      HBA_Score = c(hba_char, hba_ds)
    )
    write.csv(hba_results, "hba_scores.csv", row.names = FALSE)
    
    # 4. Calculate local HBA scores for 13 subnucleosomal segments
    local_hba_scores <- localHBA(inseq = inseq, species = "sc")
    
    # Save local HBA scores to a CSV file
    local_hba_df <- data.frame(
      Segment = names(local_hba_scores),
      Local_HBA = as.numeric(local_hba_scores)
    )
    write.csv(local_hba_df, "local_hba_scores.csv", row.names = FALSE)
    
    # 5. Visualize local HBA scores using a barplot and save as PDF
    pdf("local_hba_barplot.pdf", width = 8, height = 6)
    barplot(
      localHBA(inseq = inseq, species = "sc"), 
      names.arg = LETTERS[1:13], 
      xlab = "Nucleosomal subsegments", 
      ylab = "local HBA", 
      main = "Local HBA scores for inseq"
    )
    dev.off()

    writeLines(c(
        '"BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION":',
        paste0('    nuCpos: ', as.character(packageVersion('nuCpos')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucleosome_affinity_prediction.csv versions.yml
    """
}

workflow BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence.RData, sequence_DNAString.RData ] ]

    main:
    BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION(ch_input)

    emit:
    tables   = BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION.out.tables
    plots    = BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION.out.plots
    objects  = BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION.out.objects
    versions = BIOC_NUCPOS_NUCLEOSOME_AFFINITY_PREDICTION.out.versions
}
