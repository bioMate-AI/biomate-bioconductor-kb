#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ldblock — snp_set_expansion
// Expand a set of target SNPs to include all SNPs in linkage disequilibrium above a specified threshold using population LD data.
// Input: ld_data.txt.gz, target_snps.txt
// Container: quay.io/biocontainers/bioconductor-ldblock:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, Matrix, ldblock
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import HapMap-formatted LD data using hmld
//  * 2. [Input & Preparation] Define the target SNP set
//  * 3. [Core Analysis] Expand the SNP set based on an LD threshold using expandSnpSet

nextflow.enable.dsl = 2

process BIOC_LDBLOCK_SNP_SET_EXPANSION {
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
    .bm_deps <- c("ldblock", "GenomeInfoDb", "Matrix")
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
    suppressPackageStartupMessages({
      library(ldblock)
      library(GenomeInfoDb)
      library(Matrix)
    })
    
    # Verify input files exist
    if (!file.exists("ld_data.txt.gz")) {
      stop("Required input file 'ld_data.txt.gz' not found in the working directory.")
    }
    if (!file.exists("target_snps.txt")) {
      stop("Required input file 'target_snps.txt' not found in the working directory.")
    }
    
    # 1. Import HapMap-formatted LD data using hmld
    # We stage the input file in a temporary directory with the expected HapMap naming convention
    # so that hmld can correctly identify it using poptag and chrom.
    tmp_dir <- tempfile("hapmap_stage")
    dir.create(tmp_dir, recursive = TRUE)
    file.copy("ld_data.txt.gz", file.path(tmp_dir, "ld_chr17_CEU.txt.gz"))
    
    path = dir(tmp_dir, full=TRUE)
    ceu17 = hmld(path, poptag="CEU", chrom="chr17")
    
    # 2. Define the target SNP set
    # Read the target SNPs from the user-provided file
    rsh17 = scan("target_snps.txt", what = character(), quiet = TRUE)
    rsh17 = unique(rsh17)
    
    # 3. Expand the SNP set based on an LD threshold using expandSnpSet
    exset = ldblock::expandSnpSet( rsh17, ldstruct= ceu17, lb=.9 )
    
    # Save meaningful results
    # Save the expanded SNP set as a text file and CSV
    writeLines(exset, "expanded_snps.txt")
    write.csv(data.frame(SNP = exset), "expanded_snps.csv", row.names = FALSE)
    
    # Save the ldstruct object
    saveRDS(ceu17, "ceu17_ldstruct.rds")
    
    # Generate and save the LD block plot
    pdf("ld_block_plot.pdf")
    n_limit <- min(400, nrow(ceu17@ldmat))
    if (n_limit > 0) {
      image(ceu17@ldmat[1:n_limit, 1:n_limit], 
            col.reg=heat.colors(120), colorkey=TRUE, useRaster=TRUE)
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'expanded_snps.txt', 'expanded_snps.csv', 'ceu17_ldstruct.rds', and 'ld_block_plot.pdf'.")

    writeLines(c(
        '"BIOC_LDBLOCK_SNP_SET_EXPANSION":',
        paste0('    ldblock: ', as.character(packageVersion('ldblock')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_set_expansion.csv versions.yml
    """
}

workflow BIOC_LDBLOCK_SNP_SET_EXPANSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ld_data.txt.gz, target_snps.txt ] ]

    main:
    BIOC_LDBLOCK_SNP_SET_EXPANSION(ch_input)

    emit:
    tables   = BIOC_LDBLOCK_SNP_SET_EXPANSION.out.tables
    plots    = BIOC_LDBLOCK_SNP_SET_EXPANSION.out.plots
    objects  = BIOC_LDBLOCK_SNP_SET_EXPANSION.out.objects
    versions = BIOC_LDBLOCK_SNP_SET_EXPANSION.out.versions
}
