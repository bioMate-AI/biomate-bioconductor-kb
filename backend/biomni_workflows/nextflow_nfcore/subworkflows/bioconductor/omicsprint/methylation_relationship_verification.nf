#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: omicsPrint — methylation_relationship_verification
// Verify sample relationships using DNA methylation beta-values by first converting them to genotypes.
// Input: se, r, hm450.manifest.pop.GoNL
// Container: quay.io/biocontainers/bioconductor-omicsprint:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, SummarizedExperiment, omicsPrint
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Filter SummarizedExperiment for CpGs affected by polymorphic SNPs
//  * 2. [Core Analysis] Convert beta-values to genotype calls using beta2genotype
//  * 3. [Core Analysis] Calculate allele sharing using alleleSharing
//  * 4. [Core Analysis] Infer and identify misclassified relationships using inferRelations

nextflow.enable.dsl = 2

process BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("omicsPrint", "GenomicRanges")
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
        library(omicsPrint)
        library(GenomicRanges)
        
        # Helper function to locate and read the user input files
        load_input_file <- function(filename, expected_type = "rds") {
          # Check for exact filename first, then with extension
          possible_paths <- c(filename, paste0(filename, ".", expected_type))
          
          for (path in possible_paths) {
            if (file.exists(path)) {
              message(paste("Loading input file:", path))
              if (expected_type == "rds") {
                return(readRDS(path))
              } else if (expected_type == "csv") {
                return(read.csv(path, stringsAsFactors = FALSE))
              }
            }
          }
          stop(paste("Required input file not found:", filename))
        }
        
        # 1. Load User Inputs
        se <- load_input_file("se", "rds")
        hm450.manifest.pop.GoNL <- load_input_file("hm450.manifest.pop.GoNL", "rds")
        
        # 'r' could be saved as RDS or CSV, attempt RDS first, then CSV
        r <- tryCatch({
          load_input_file("r", "rds")
        }, error = function(e) {
          load_input_file("r", "csv")
        })
        
        # 2. Filter SummarizedExperiment for CpGs affected by polymorphic SNPs
        cpgs <- names(hm450.manifest.pop.GoNL[
            mcols(hm450.manifest.pop.GoNL)\$MASK.snp5.EAS])
        se <- se[intersect(cpgs, rownames(se)),]
        
        # 3. Convert beta-values to genotype calls using beta2genotype
        dnamCalls <- beta2genotype(se, assayName = assayNames(se)[1])
        
        # 4. Calculate allele sharing using alleleSharing
        data <- alleleSharing(dnamCalls, relations = r, verbose = TRUE)
        
        # 5. Infer and identify misclassified relationships using inferRelations
        # We wrap this in a PDF device to capture the classification boundary plot
        pdf("relationship_verification_plots.pdf", width = 7, height = 7)
        mismatches <- inferRelations(data)
        dev.off()
        
        # 6. Write outputs to the working directory
        message("Writing output files...")
        write.csv(as.data.frame(dnamCalls), "dnam_genotype_calls.csv", row.names = TRUE)
        write.csv(data, "allele_sharing_results.csv", row.names = FALSE)
        write.csv(mismatches, "inferred_mismatches.csv", row.names = FALSE)
        
        saveRDS(dnamCalls, "dnam_genotype_calls.rds")
        saveRDS(data, "allele_sharing_results.rds")
        saveRDS(mismatches, "inferred_mismatches.rds")
        
        message("Workflow completed successfully.")

    writeLines(c(
        '"BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION":',
        paste0('    omicsPrint: ', as.character(packageVersion('omicsPrint')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_relationship_verification.csv versions.yml
    """
}

workflow BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se, r, hm450.manifest.pop.GoNL ] ]

    main:
    BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION(ch_input)

    emit:
    tables   = BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION.out.tables
    plots    = BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION.out.plots
    objects  = BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION.out.objects
    versions = BIOC_OMICSPRINT_METHYLATION_RELATIONSHIP_VERIFICATION.out.versions
}
