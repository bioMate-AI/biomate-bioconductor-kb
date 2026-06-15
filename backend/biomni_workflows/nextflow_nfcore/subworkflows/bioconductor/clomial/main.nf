#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Clomial — clonal_decomposition
// Infer clonal genotypes and frequencies from multi-sample tumor NGS count data using binomial models.
// Input: Dc, Dt
// Container: quay.io/biocontainers/bioconductor-clomial:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Clomial
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the Clomial package and input count matrices
//  * 2. [Core Analysis] Run the Clomial EM algorithm to train multiple models
//  * 3. [Core Analysis] Select the best model based on likelihood using choose.best()
//  * 4. [Core Analysis] Extract and inspect the estimated clonal genotypes (Mu) and clone frequencies (P)

nextflow.enable.dsl = 2

process BIOC_CLOMIAL_CLONAL_DECOMPOSITION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("Clomial")
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
    
    # Load Clomial package
    library(Clomial)
    
    # Set seed for reproducibility
    set.seed(1)
    
    # Read input matrices Dc and Dt from the working directory
    if (file.exists("Dc.csv")) {
      Dc <- as.matrix(read.csv("Dc.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Dc.tsv")) {
      Dc <- as.matrix(read.delim("Dc.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Dc.txt")) {
      Dc <- as.matrix(read.table("Dc.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Dc file not found in working directory (expected Dc.csv, Dc.tsv, or Dc.txt)")
    }
    
    if (file.exists("Dt.csv")) {
      Dt <- as.matrix(read.csv("Dt.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Dt.tsv")) {
      Dt <- as.matrix(read.delim("Dt.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Dt.txt")) {
      Dt <- as.matrix(read.table("Dt.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Dt file not found in working directory (expected Dt.csv, Dt.tsv, or Dt.txt)")
    }
    
    # Run Clomial EM algorithm to train multiple models
    Clomial2 <- Clomial(Dc=Dc, Dt=Dt, maxIt=20, C=4, binomTryNum=2)
    
    # Extract the first model
    model1 <- Clomial2\$models[[1]]
    
    # Print clonal frequencies of the first model
    print("Clonal frequencies of the first model:")
    print(round(model1\$P, digits=2))
    
    # Select the best model based on likelihood using choose.best()
    models <- Clomial2\$models
    print(paste("Number of trained models:", length(models)))
    
    chosen <- choose.best(models=models, doTalk=TRUE)
    M1 <- chosen\$bestModel
    
    # Extract and inspect the estimated clonal genotypes (Mu) and clone frequencies (P)
    print("Genotypes according to the best model:")
    print(round(M1\$Mu))
    
    print("Clone frequencies in the first sample:")
    print(round(M1\$P[,1], digits=2))
    
    # Write outputs to files
    saveRDS(Clomial2, file = "clomial_output.rds")
    saveRDS(M1, file = "best_model.rds")
    write.csv(round(M1\$Mu), file = "best_model_genotypes_Mu.csv", row.names = TRUE)
    write.csv(round(M1\$P, digits = 2), file = "best_model_frequencies_P.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CLOMIAL_CLONAL_DECOMPOSITION":',
        paste0('    Clomial: ', as.character(packageVersion('Clomial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clonal_decomposition.csv versions.yml
    """
}

workflow BIOC_CLOMIAL_CLONAL_DECOMPOSITION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Dc, Dt ] ]

    main:
    BIOC_CLOMIAL_CLONAL_DECOMPOSITION(ch_input)

    emit:
    tables   = BIOC_CLOMIAL_CLONAL_DECOMPOSITION.out.tables
    plots    = BIOC_CLOMIAL_CLONAL_DECOMPOSITION.out.plots
    objects  = BIOC_CLOMIAL_CLONAL_DECOMPOSITION.out.objects
    versions = BIOC_CLOMIAL_CLONAL_DECOMPOSITION.out.versions
}
