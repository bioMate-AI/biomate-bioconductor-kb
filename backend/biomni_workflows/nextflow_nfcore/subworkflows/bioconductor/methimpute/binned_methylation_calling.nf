#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methimpute — binned_methylation_calling
// Call and impute methylation status on binned genomic data (e.g., 100bp bins).
// Input: arabidopsis_bsseeker.txt.gz, arabidopsis_sequence.fa.gz
// Container: quay.io/biocontainers/bioconductor-methimpute:1.32.0--r45ha27e39d_0
// R packages: methimpute
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-methimpute:1.32.0--r45ha27e39d_0"

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
    library(methimpute)
    
    # Define input files (expected to be in the working directory)
    file <- "arabidopsis_bsseeker.txt.gz"
    fasta.file <- "arabidopsis_sequence.fa.gz"
    
    # Verify input files exist
    if (!file.exists(file)) {
      stop(paste("Required input file missing in working directory:", file))
    }
    if (!file.exists(fasta.file)) {
      stop(paste("Required input file missing in working directory:", fasta.file))
    }
    
    # --- Import the BSSeeker data ---
    message("Importing BSSeeker data...")
    bsseeker.data <- importBSSeeker(file)
    print(bsseeker.data)
    
    # --- Extract all genomic cytosine positions from the FASTA ---
    message("Extracting cytosine positions from FASTA...")
    cytosine.positions <- extractCytosinesFromFASTA(fasta.file,
                                                    contexts = c('CG','CHG','CHH'))
    
    # --- Inflate the methylome to include non-covered cytosines ---
    message("Inflating methylome...")
    methylome <- inflateMethylome(bsseeker.data, cytosine.positions)
    print(methylome)
    
    # --- Bin the inflated methylome into fixed-size windows ---
    message("Binning methylome...")
    binnedMethylome <- binMethylome(methylome, binsize = 100, contexts = c('total','CG'))
    print(binnedMethylome\$CG)
    
    # --- Call and impute methylation status on the binned data ---
    message("Calling methylation on binned data...")
    binnedModel <- callMethylation(data = binnedMethylome\$CG)
    print(binnedModel)
    
    # Save the model object and export results
    message("Saving binned model to RDS...")
    saveRDS(binnedModel, file = "binned_model.rds")
    
    message("Exporting binned model data to CSV...")
    binned_df <- as.data.frame(binnedModel\$data)
    write.csv(binned_df, file = "binned_methylation_calls.csv", row.names = FALSE)
    
    # --- Plot diagnostics and save to PDF ---
    message("Generating diagnostic plots...")
    pdf("binned_methylation_plots.pdf", width = 8, height = 6)
    
    # Plot convergence
    p1 <- plotConvergence(binnedModel)
    print(p1)
    
    # Plot transition probabilities
    p2 <- plotTransitionProbs(binnedModel)
    print(p2)
    
    # Plot histogram
    p3 <- plotHistogram(binnedModel, total.counts = 150)
    print(p3)
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING":',
        paste0('        methimpute: ', as.character(packageVersion("methimpute")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binned_methylation_calling.csv versions.yml
    """
}

workflow BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arabidopsis_bsseeker.txt.gz, arabidopsis_sequence.fa.gz ] ]

    main:
    BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING(ch_input)

    emit:
    tables   = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.tables
    plots    = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.plots
    objects  = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.objects
    versions = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.versions
}
