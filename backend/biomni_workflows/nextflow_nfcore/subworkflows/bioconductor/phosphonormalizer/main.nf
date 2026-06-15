#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phosphonormalizer — pairwise_phospho_normalization
// Normalize enriched phosphoproteomics data using overlapping peptides from non-enriched data to correct for enrichment-induced bias.
// Input: enriched_data.csv, non_enriched_data.csv
// Container: quay.io/biocontainers/bioconductor-phosphonormalizer:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: phosphonormalizer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define abundance column indices for enriched and non-enriched datasets
//  * 2. [Input & Preparation] Define sequence and modification column indices
//  * 3. [Input & Preparation] Define technical replicates as a factor
//  * 4. [Visualization & Output] Specify plot parameters for fold change distribution
//  * 5. [Core Analysis] Run normalizePhospho to perform pairwise normalization

nextflow.enable.dsl = 2

process BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("phosphonormalizer")
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
            
            # Load the required library
            library(phosphonormalizer)
            
            # Read the user input files from the working directory
            enriched.rd <- read.csv("enriched_data.csv", stringsAsFactors = FALSE)
            non.enriched.rd <- read.csv("non_enriched_data.csv", stringsAsFactors = FALSE)
            
            # Ensure sequence and modification columns are character format
            enriched.rd[[1]] <- as.character(enriched.rd[[1]])
            enriched.rd[[2]] <- as.character(enriched.rd[[2]])
            non.enriched.rd[[1]] <- as.character(non.enriched.rd[[1]])
            non.enriched.rd[[2]] <- as.character(non.enriched.rd[[2]])
            
            # Ensure abundance columns are numeric format
            for (i in 3:ncol(enriched.rd)) {
              enriched.rd[[i]] <- as.numeric(enriched.rd[[i]])
            }
            for (i in 3:ncol(non.enriched.rd)) {
              non.enriched.rd[[i]] <- as.numeric(non.enriched.rd[[i]])
            }
            
            # 1. Define abundance column indices for enriched and non-enriched datasets
            samplesCols <- data.frame(enriched=3:ncol(enriched.rd), non.enriched=3:ncol(non.enriched.rd))
            
            # 2. Define sequence and modification column indices
            modseqCols <- data.frame(enriched = 1:2, non.enriched = 1:2)
            
            # 3. Define technical replicates as a factor
            # Dynamically group replicates by removing common trailing suffixes (e.g., .1, _1) from column names
            tech_names <- gsub("[-_\\\\.][0-9]+\$", "", colnames(enriched.rd)[3:ncol(enriched.rd)])
            techRep <- factor(tech_names, levels = unique(tech_names))
            
            # 4. Specify plot parameters for fold change distribution
            plot.param <- list(
              control = levels(techRep)[1], 
              samples = levels(techRep)[min(2, length(levels(techRep)))]
            )
            
            # 5. Run normalizePhospho to perform pairwise normalization
            # We wrap this in a PDF device to capture the generated fold change distribution plots
            pdf("fold_change_distribution_plots.pdf", width = 7, height = 5)
            
            norm <- normalizePhospho(
              enriched = enriched.rd, 
              non.enriched = non.enriched.rd, 
              samplesCols = samplesCols, 
              modseqCols = modseqCols, 
              techRep = techRep, 
              plot.fc = plot.param
            )
            
            dev.off()
            
            # Write the meaningful results to output files
            write.csv(norm, "normalized_enriched_data.csv", row.names = FALSE)
            saveRDS(norm, "normalized_enriched_data.rds")

    writeLines(c(
        '"BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION":',
        paste0('    phosphonormalizer: ', as.character(packageVersion('phosphonormalizer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_phospho_normalization.csv versions.yml
    """
}

workflow BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ enriched_data.csv, non_enriched_data.csv ] ]

    main:
    BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION.out.tables
    plots    = BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION.out.plots
    objects  = BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION.out.objects
    versions = BIOC_PHOSPHONORMALIZER_PAIRWISE_PHOSPHO_NORMALIZATION.out.versions
}
