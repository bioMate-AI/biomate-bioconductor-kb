#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Summix — allele_frequency_adjustment
// Adjust observed allele frequencies to match the substructure proportions of a target sample or individual.
// Input: ancestryData
// Container: quay.io/biocontainers/bioconductor-summix:2.16.0--r45hdfd78af_0
// Requires: Summix
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data. 2. Run adjAF() with target and observed proportions, reference and observed sample sizes, and adjustmen

nextflow.enable.dsl = 2

process BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the required package
    library(Summix)
    
    # 1. Load the user-provided data
    # The pipeline expects 'ancestryData' in the working directory (as CSV, TSV, or RDS)
    if (file.exists("ancestryData.csv")) {
      ancestryData <- read.csv("ancestryData.csv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("ancestryData.tsv")) {
      ancestryData <- read.delim("ancestryData.tsv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("ancestryData.rds")) {
      ancestryData <- readRDS("ancestryData.rds")
    } else if (file.exists("ancestryData")) {
      ancestryData <- tryCatch({
        read.csv("ancestryData", header = TRUE, stringsAsFactors = FALSE)
      }, error = function(e) {
        read.delim("ancestryData", header = TRUE, stringsAsFactors = FALSE)
      })
    } else {
      stop("Required input file 'ancestryData' (CSV, TSV, or RDS format) not found in the working directory.")
    }
    
    # 2. Run adjAF() with target and observed proportions, reference and observed sample sizes, and adjustment method
    adjusted_data <- adjAF(
      data = ancestryData,
      reference = c("reference_AF_afr", "reference_AF_eur", "reference_AF_iam"),
      observed = "gnomad_AF_afr",
      pi.target = c(1, 0, 0),
      pi.observed = c(0.812142, 0.169953, 0.017905),
      adj_method = 'average',
      N_reference = c(704, 741, 47),
      N_observed = 20744,
      filter = TRUE
    )
    
    # 3. Inspect the adjusted allele frequencies
    cat("First 5 rows of adjusted allele frequencies:\n")
    print(adjusted_data\$adjusted.AF[1:5, ])
    
    # 4. Write named output files for the meaningful results
    # Save the complete adjusted data list object
    saveRDS(adjusted_data, file = "adjusted_data.rds")
    
    # Save the adjusted allele frequencies table
    write.csv(adjusted_data\$adjusted.AF, file = "adjusted_allele_frequencies.csv", row.names = FALSE)
    
    # Save the mixture proportions summary table
    write.csv(adjusted_data\$pi, file = "adjustment_proportions_summary.csv", row.names = FALSE)
    
    # Save metadata summary (effective sample size, number of SNPs, etc.)
    summary_metadata <- data.frame(
      Metric = c("Observed_Data_Column", "Number_of_SNPs", "Effective_Sample_Size"),
      Value = c(
        as.character(adjusted_data\$observed.data),
        as.character(adjusted_data\$Nsnps),
        as.character(adjusted_data\$effective.sample.size)
      ),
      stringsAsFactors = FALSE
    )
    write.csv(summary_metadata, file = "adjustment_metadata.csv", row.names = FALSE)
    
    cat("\nPipeline completed successfully. Outputs saved:\n")
    cat("- adjusted_data.rds\n")
    cat("- adjusted_allele_frequencies.csv\n")
    cat("- adjustment_proportions_summary.csv\n")
    cat("- adjustment_metadata.csv\n")

    writeLines(c(
        '"BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT":',
        paste0('    Summix: ', as.character(packageVersion('Summix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allele_frequency_adjustment.csv versions.yml
    """
}

workflow BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ancestryData ] ]

    main:
    BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT(ch_input)

    emit:
    tables   = BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT.out.tables
    plots    = BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT.out.plots
    objects  = BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT.out.objects
    versions = BIOC_SUMMIX_ALLELE_FREQUENCY_ADJUSTMENT.out.versions
}
