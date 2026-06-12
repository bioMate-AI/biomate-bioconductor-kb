#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mpra — allelic_comparison
// Perform differential activity analysis between alleles of regulatory elements measured in the same samples (paired analysis).
// Input: agg_dna.txt, agg_rna.txt, eid.txt, eseq.txt
// Container: quay.io/biocontainers/bioconductor-mpra:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, mpra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create an MPRASet object using MPRASet()
//  * 2. [Input & Preparation] Define the design matrix and block vector
//  * 3. [Core Analysis] Fit the model using mpralm() with model_type = "corr_groups" and specifying the block vector
//  * 4. [Core Analysis] Extract top differential elements using topTable()

nextflow.enable.dsl = 2

process BIOC_MPRA_ALLELIC_COMPARISON {
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
    .bm_deps <- c("mpra", "limma")
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
        library(mpra)
        library(limma)
        
        # 1. Read user input files from the working directory
        if (!file.exists("agg_dna.txt") || !file.exists("agg_rna.txt") || !file.exists("eid.txt")) {
          stop("Required input files (agg_dna.txt, agg_rna.txt, eid.txt) are missing from the working directory.")
        }
        
        agg_dna <- as.matrix(read.table("agg_dna.txt", header = TRUE, row.names = 1, sep = ""))
        agg_rna <- as.matrix(read.table("agg_rna.txt", header = TRUE, row.names = 1, sep = ""))
        eid <- readLines("eid.txt")
        
        eseq <- NULL
        if (file.exists("eseq.txt") && file.info("eseq.txt")\$size > 0) {
          eseq <- readLines("eseq.txt")
        }
        
        # 2. Create MPRASet object
        mpraset_example2 <- MPRASet(DNA = agg_dna, RNA = agg_rna, eid = eid, eseq = eseq, barcode = NULL)
        
        # Assign to the variable name used in the documented analysis code
        mpraSetAllelicExample <- mpraset_example2
        
        # 3. Define design matrix and block vector
        # Use positional assignment for alleles (first half = allele A, second half = allele B)
        # to avoid relying on hardcoded column name strings.
        design <- data.frame(intcpt = 1, alleleB = rep(c(FALSE, TRUE), each = ncol(mpraSetAllelicExample) / 2))
        
        # Handle block_vector dynamically to prevent dimension mismatch if input size differs from 10,
        # while preserving the exact documented code for the standard case.
        if (ncol(mpraSetAllelicExample) == 10) {
          block_vector <- rep(1:5, 2)
        } else {
          block_vector <- rep(seq_len(ncol(mpraSetAllelicExample) / 2), 2)
        }
        
        # 4. Fit the model using mpralm and save the diagnostic plot
        pdf("mpralm_allele_plot.pdf")
        mpralm_allele_fit <- mpralm(object = mpraSetAllelicExample, design = design, aggregate = "none", normalize = TRUE, block = block_vector, model_type = "corr_groups", plot = TRUE)
        dev.off()
        
        # 5. Extract top differential elements
        toptab_allele <- topTable(mpralm_allele_fit, coef = 2, number = Inf)
        head(toptab_allele)
        
        # 6. Save outputs to files
        write.csv(toptab_allele, "toptab_allele.csv", row.names = TRUE)
        saveRDS(mpraset_example2, "mpraset_example2.rds")
        saveRDS(mpralm_allele_fit, "mpralm_allele_fit.rds")

    writeLines(c(
        '"BIOC_MPRA_ALLELIC_COMPARISON":',
        paste0('    mpra: ', as.character(packageVersion('mpra')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allelic_comparison.csv versions.yml
    """
}

workflow BIOC_MPRA_ALLELIC_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ agg_dna.txt, agg_rna.txt, eid.txt, eseq.txt ] ]

    main:
    BIOC_MPRA_ALLELIC_COMPARISON(ch_input)

    emit:
    tables   = BIOC_MPRA_ALLELIC_COMPARISON.out.tables
    plots    = BIOC_MPRA_ALLELIC_COMPARISON.out.plots
    objects  = BIOC_MPRA_ALLELIC_COMPARISON.out.objects
    versions = BIOC_MPRA_ALLELIC_COMPARISON.out.versions
}
