#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: omicsPrint — genotype_relationship_verification
// Verify sample relationships using SNP/genotype matrices within a single omic dataset or across two different omic datasets.
// Input: x, y, relations
// Container: quay.io/biocontainers/bioconductor-omicsprint:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: omicsPrint
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate allele sharing using Identity by State (IBS) with alleleSharing
//  * 2. [Core Analysis] Infer and identify misclassified relationships using inferRelations

nextflow.enable.dsl = 2

process BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION {
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
    .bm_deps <- c("omicsPrint")
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
        library(omicsPrint)
        
        # Helper function to read input matrices (x or y)
        read_input_matrix <- function(base_name) {
          if (file.exists(paste0(base_name, ".csv"))) {
            df <- read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)
            return(as.matrix(df))
          } else if (file.exists(paste0(base_name, ".tsv"))) {
            df <- read.delim(paste0(base_name, ".tsv"), row.names = 1, check.names = FALSE)
            return(as.matrix(df))
          } else if (file.exists(paste0(base_name, ".rds"))) {
            obj <- readRDS(paste0(base_name, ".rds"))
            return(as.matrix(obj))
          }
          return(NULL)
        }
        
        # Helper function to read relations data frame
        read_relations_df <- function() {
          if (file.exists("relations.csv")) {
            return(read.csv("relations.csv", check.names = FALSE))
          } else if (file.exists("relations.tsv")) {
            return(read.delim("relations.tsv", check.names = FALSE))
          } else if (file.exists("relations.rds")) {
            return(readRDS("relations.rds"))
          }
          return(NULL)
        }
        
        # 1. Read required input 'x'
        x <- read_input_matrix("x")
        if (is.null(x)) {
          stop("Error: Required input file 'x' (genotype matrix) not found in the working directory.")
        }
        
        # 2. Run allele sharing and relationship inference within a single dataset (x)
        message("Running allele sharing on x...")
        data <- alleleSharing(x, verbose=TRUE)
        saveRDS(data, "allele_sharing_x.rds")
        
        message("Inferring relations on x...")
        pdf("mismatches_x_no_relations.pdf")
        mismatches <- inferRelations(data)
        dev.off()
        write.csv(mismatches, "mismatches_x_no_relations.csv", row.names = FALSE)
        
        # 3. Handle relations (either user-provided or constructed)
        user_relations <- read_relations_df()
        if (!is.null(user_relations)) {
          message("Using user-provided relations...")
          relations <- user_relations
        } else {
          message("Constructing default relations...")
          relations <- expand.grid(idx = colnames(x), idy = colnames(x))
          relations\$relation_type <- "unrelated"
          relations\$relation_type[relations\$idx == relations\$idy] <- "identical"
        }
        write.csv(relations, "relations_used.csv", row.names = FALSE)
        
        # 4. Run allele sharing with relations on x
        message("Running allele sharing on x with relations...")
        data <- alleleSharing(x, relations=relations)
        saveRDS(data, "allele_sharing_x_with_relations.rds")
        
        message("Inferring relations on x with relations...")
        pdf("mismatches_x_with_relations.pdf")
        mismatches <- inferRelations(data)
        dev.off()
        write.csv(mismatches, "mismatches_x_with_relations.csv", row.names = FALSE)
        
        # 5. Run cross-omic relationship verification if 'y' is provided
        y <- read_input_matrix("y")
        if (!is.null(y)) {
          message("Optional input 'y' detected. Running cross-omic verification...")
          
          # Verify allele sharing between x and y without relations
          message("Running allele sharing between x and y...")
          data_xy <- alleleSharing(x, y)
          saveRDS(data_xy, "allele_sharing_xy.rds")
          
          message("Inferring relations between x and y...")
          pdf("mismatches_xy_no_relations.pdf")
          mismatches_xy <- inferRelations(data_xy)
          dev.off()
          write.csv(mismatches_xy, "mismatches_xy_no_relations.csv", row.names = FALSE)
          
          # Verify allele sharing between x and y with relations
          message("Running allele sharing between x and y with relations...")
          data_xy_rel <- alleleSharing(x, y, relations)
          saveRDS(data_xy_rel, "allele_sharing_xy_with_relations.rds")
          
          message("Inferring relations between x and y with relations...")
          pdf("mismatches_xy_with_relations.pdf")
          mismatches_xy_rel <- inferRelations(data_xy_rel)
          dev.off()
          write.csv(mismatches_xy_rel, "mismatches_xy_with_relations.csv", row.names = FALSE)
        } else {
          message("Optional input 'y' not provided. Skipping cross-omic verification.")
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION":',
        paste0('    omicsPrint: ', as.character(packageVersion('omicsPrint')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genotype_relationship_verification.csv versions.yml
    """
}

workflow BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x, y, relations ] ]

    main:
    BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION(ch_input)

    emit:
    tables   = BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION.out.tables
    plots    = BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION.out.plots
    objects  = BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION.out.objects
    versions = BIOC_OMICSPRINT_GENOTYPE_RELATIONSHIP_VERIFICATION.out.versions
}
