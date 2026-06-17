#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SparseSignatures — mutational_signature_discovery
// Extract and visualize de novo sparse mutational signatures from patient point mutation data.
// Input: ssm560_reduced, BSgenome.Hsapiens.1000genomes.hs37d5
// Container: quay.io/biocontainers/bioconductor-sparsesignatures:2.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.1000genomes.hs37d5, SparseSignatures
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load mutation data and reference genome
//  * 2. [Input & Preparation] Convert mutation data to a 96-trinucleotide count matrix using import.trinucleotides.counts
//  * 3. [Visualization & Output] Plot patient mutation counts using patients.plot
//  * 4. [Core Analysis] Estimate starting beta values using startingBetaEstimation
//  * 5. [Core Analysis] Evaluate the range of LASSO penalty values using lambdaRangeBetaEvaluation
//  * 6. [Core Analysis] Perform cross-validation to select the optimal number of signatures (K) and lambda using nmfLassoCV
//  * 7. [Core Analysis] Extract signatures using nmfLasso with the selected parameters
//  * 8. [Visualization & Output] Plot the discovered signatures using signatures.plot

nextflow.enable.dsl = 2

process BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("SparseSignatures", "BSgenome.Hsapiens.1000genomes.hs37d5")
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
    library("SparseSignatures")
    library("BSgenome.Hsapiens.1000genomes.hs37d5")
    
    # 1. Load mutation data and reference genome
    if (file.exists("ssm560_reduced.rds")) {
      ssm560_reduced <- readRDS("ssm560_reduced.rds")
    } else if (file.exists("ssm560_reduced.csv")) {
      ssm560_reduced <- read.csv("ssm560_reduced.csv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("ssm560_reduced")) {
      ssm560_reduced <- read.csv("ssm560_reduced", header = TRUE, stringsAsFactors = FALSE)
    } else {
      stop("Required input file 'ssm560_reduced' not found in the working directory.")
    }
    
    if (file.exists("BSgenome.Hsapiens.1000genomes.hs37d5.rds")) {
      bsg <- readRDS("BSgenome.Hsapiens.1000genomes.hs37d5.rds")
    } else {
      bsg <- BSgenome.Hsapiens.1000genomes.hs37d5
    }
    
    if (file.exists("background.rds")) {
      background <- readRDS("background.rds")
    } else {
      background <- SparseSignatures::background
    }
    
    # 2. Convert mutation data to a 96-trinucleotide count matrix
    imported_data = import.trinucleotides.counts(data=ssm560_reduced, reference=bsg)
    write.csv(imported_data, "imported_trinucleotides_counts.csv", row.names = TRUE)
    
    # 3. Plot patient mutation counts
    pdf("patients_plot.pdf", width = 10, height = 7)
    tryCatch({
      patients.plot(trinucleotides_counts=imported_data, samples="PD10010a")
    }, error = function(e) {
      # Fallback to the first available sample if PD10010a is not present
      if (nrow(imported_data) > 0) {
        patients.plot(trinucleotides_counts=imported_data, samples=rownames(imported_data)[1])
      } else {
        stop("Imported data is empty.")
      }
    })
    dev.off()
    
    # 4. Estimate starting beta values
    patients = imported_data
    starting_betas = startingBetaEstimation(x=patients, K=3:12, background_signature=background)
    saveRDS(starting_betas, "starting_betas.rds")
    
    # 5. Evaluate the range of LASSO penalty values
    lambda_range = lambdaRangeBetaEvaluation(x=patients, K=10, beta=starting_betas[[8,1]], lambda_values=c(0.05,0.10))
    saveRDS(lambda_range, "lambda_range.rds")
    
    # 6. Perform cross-validation to select the optimal number of signatures (K) and lambda
    cv = nmfLassoCV(x=patients, K=3:10)
    saveRDS(cv, "cv_results.rds")
    
    # 7. Extract signatures using nmfLasso
    beta = starting_betas[["5_signatures", "Value"]]
    res = nmfLasso(x = patients, K = 5, beta = beta, background_signature = background, seed = 12345)
    saveRDS(res, "nmf_Lasso_results.rds")
    
    # 8. Plot the discovered signatures
    signatures = res\$beta
    write.csv(signatures, "discovered_signatures.csv", row.names = TRUE)
    
    pdf("signatures_plot.pdf", width = 10, height = 7)
    signatures.plot(beta=signatures, xlabels=FALSE)
    dev.off()

    writeLines(c(
        '"BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY":',
        paste0('    SparseSignatures: ', as.character(packageVersion('SparseSignatures')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mutational_signature_discovery.csv versions.yml
    """
}

workflow BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ssm560_reduced, BSgenome.Hsapiens.1000genomes.hs37d5 ] ]

    main:
    BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY.out.tables
    plots    = BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY.out.plots
    objects  = BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY.out.objects
    versions = BIOC_SPARSESIGNATURES_MUTATIONAL_SIGNATURE_DISCOVERY.out.versions
}
