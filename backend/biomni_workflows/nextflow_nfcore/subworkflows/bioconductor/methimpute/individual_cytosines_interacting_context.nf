#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methimpute — individual_cytosines_interacting_context
// Call and impute methylation status for individual cytosines using a single HMM that considers both within-context and between-context correlations.
// Input: bsseeker_file.txt.gz, genome_sequence.fa.gz
// Container: quay.io/biocontainers/bioconductor-methimpute:1.32.0--r45ha27e39d_0
// R packages: methimpute
// Bioconductor: 3.20 | R: 4.4
// Requires: methimpute
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import BSSeeker data
//  * 2. [Core Analysis] Extract genomic cytosine positions from FASTA
//  * 3. [Core Analysis] Inflate the methylome to include non-covered cytosines
//  * 4. [Core Analysis] Calculate distance correlation across all contexts
//  * 5. [Core Analysis] Estimate transition distance parameters
//  * 6. [Core Analysis] Call methylation status using the interacting-context model
//  * 7. [Visualization & Output] Export results

nextflow.enable.dsl = 2

process BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT {
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
    .bm_deps <- c("methimpute")
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
    
    # Load required library
    library(methimpute)
    
    # Define input files from the working directory
    file <- "bsseeker_file.txt.gz"
    fasta.file <- "genome_sequence.fa.gz"
    
    # Check if input files exist
    if (!file.exists(file)) {
      stop(paste("Required input file missing:", file))
    }
    if (!file.exists(fasta.file)) {
      stop(paste("Required input file missing:", fasta.file))
    }
    
    # ===== Step 1: Import BSSeeker data =====
    message("Importing BSSeeker data...")
    bsseeker.data <- importBSSeeker(file)
    
    # ===== Step 2: Extract genomic cytosine positions from FASTA =====
    message("Extracting cytosine positions from FASTA...")
    cytosine.positions <- extractCytosinesFromFASTA(fasta.file,
                                                    contexts = c('CG','CHG','CHH'))
    
    # ===== Step 3: Inflate the methylome to include non-covered cytosines =====
    message("Inflating methylome...")
    methylome <- inflateMethylome(bsseeker.data, cytosine.positions)
    
    # ===== Step 4: Calculate distance correlation across all contexts =====
    message("Calculating distance correlation...")
    distcor <- distanceCorrelation(methylome)
    
    # ===== Step 5: Estimate transition distance parameters =====
    message("Estimating transition distance parameters...")
    fit <- estimateTransDist(distcor)
    
    # Save transition distance fit plot and object
    saveRDS(fit, file = "transition_distance_fit.rds")
    if (!is.null(fit\$plot)) {
      pdf("distance_correlation_fit.pdf", width = 10, height = 7)
      print(fit\$plot)
      dev.off()
    }
    
    # ===== Step 6: Call methylation status using the interacting-context model =====
    message("Calling methylation status (interacting-context model)...")
    model <- callMethylation(data = methylome, transDist = fit\$transDist)
    
    # Save the complete model object
    saveRDS(model, file = "methimpute_model.rds")
    
    # Calculate and export bisulfite conversion rates
    message("Calculating bisulfite conversion rates...")
    conversion_rates <- 1 - model\$params\$emissionParams\$Unmethylated
    write.csv(as.data.frame(conversion_rates), file = "bisulfite_conversion_rates.csv", row.names = TRUE)
    
    # Generate and save diagnostic plots
    message("Generating diagnostic plots...")
    pdf("methimpute_diagnostics.pdf", width = 10, height = 7)
    tryCatch({
      print(plotConvergence(model))
    }, error = function(e) {
      message("Could not plot convergence: ", e\$message)
    })
    
    tryCatch({
      print(plotTransitionProbs(model))
    }, error = function(e) {
      message("Could not plot transition probabilities: ", e\$message)
    })
    
    tryCatch({
      print(plotHistogram(model, total.counts = 10))
    }, error = function(e) {
      message("Could not plot histogram: ", e\$message)
    })
    dev.off()
    
    # ===== Step 7: Export results =====
    message("Exporting methylome results...")
    exportMethylome(model, filename = "imputed_methylome.tsv")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT":',
        paste0('    methimpute: ', as.character(packageVersion('methimpute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_individual_cytosines_interacting_context.csv versions.yml
    """
}

workflow BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bsseeker_file.txt.gz, genome_sequence.fa.gz ] ]

    main:
    BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT(ch_input)

    emit:
    tables   = BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT.out.tables
    plots    = BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT.out.plots
    objects  = BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT.out.objects
    versions = BIOC_METHIMPUTE_INDIVIDUAL_CYTOSINES_INTERACTING_CONTEXT.out.versions
}
