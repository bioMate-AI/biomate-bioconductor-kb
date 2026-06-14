#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: unifiedWMWqPCR — qpcr_overall_normalization
// Perform differential expression analysis on RT-qPCR data using overall expression normalization when stable housekeeping genes are unavailable.
// Input: NBmat, NBgroups
// Container: quay.io/biocontainers/bioconductor-unifiedwmwqpcr:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: unifiedWMWqPCR
// Visualizations: volcano plot, forest plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the package and inspect the input qPCR data matrix
//  * 2. [Visualization & Output] Run the unified Wilcoxon-Mann-Whitney test with overall
//  * 3. [Visualization & Output] Extract and subset the test results (log odds ratios,
//  * 4. [Visualization & Output] Adjust the raw p-values for multiple testing using
//  * 5. [Visualization & Output] Create a volcano plot to visualize effect sizes and
//  * 6. [Visualization & Output] Create a forest plot to visualize estimated probabilities
//  * 7. [Visualization & Output] Extract the underlying probabilistic index model

nextflow.enable.dsl = 2

process BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("unifiedWMWqPCR")
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
    
    # Load library
    library('unifiedWMWqPCR')
    
    # --- Load the package and inspect the input qPCR data matrix ---
    # Read NBmat
    if (file.exists("NBmat.rds")) {
      NBmat <- readRDS("NBmat.rds")
    } else if (file.exists("NBmat.csv")) {
      NBmat <- as.matrix(read.csv("NBmat.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("NBmat file not found (expected NBmat.rds or NBmat.csv)")
    }
    
    # Read NBgroups
    if (file.exists("NBgroups.rds")) {
      NBgroups <- readRDS("NBgroups.rds")
    } else if (file.exists("NBgroups.csv")) {
      NBgroups <- read.csv("NBgroups.csv", header = FALSE)
      NBgroups <- as.vector(t(NBgroups))
    } else if (file.exists("NBgroups.txt")) {
      NBgroups <- readLines("NBgroups.txt")
    } else {
      stop("NBgroups file not found (expected NBgroups.rds, NBgroups.csv, or NBgroups.txt)")
    }
    
    # Inspect input data
    dim(NBmat)
    table(NBgroups)
    max(NBmat)
    
    # --- Run the unified Wilcoxon-Mann-Whitney test with overall ---
    uWMW.out <- uWMW(NBmat, groups = NBgroups)
    uWMW.out
    
    # --- Extract and subset the test results (log odds ratios, ---
    uWMW.out[1:3]
    uWMW.out[1:3,]
    names.tmp <- rownames(NBmat)[1:3]
    names.tmp
    uWMW.out[names.tmp] 
    
    selection.miRNA <- c("hsa-mir-17-3p", "hsa-mir-17-5p", "hsa-mir-18a", 
    "hsa-mir-18a#","hsa-mir-19a", "hsa-mir-19b",
    "hsa-mir-20a","hsa-mir-92", "hsa-mir-181a", "hsa-mir-181b")
    
    # Robustness check for selection.miRNA to prevent out-of-bounds errors on custom inputs
    if (!all(selection.miRNA %in% names(uWMW.out))) {
      selection.miRNA <- intersect(selection.miRNA, names(uWMW.out))
      if (length(selection.miRNA) == 0) {
        selection.miRNA <- names(uWMW.out)[1:min(10, length(uWMW.out))]
      }
    }
    
    uWMW.out[selection.miRNA]
    
    # --- Adjust the raw p-values for multiple testing using ---
    adj.pvalues <- p.adjust(uWMW.out@p.value, method = "BH")
    selection.id <- match(selection.miRNA, names(uWMW.out))
    adj.pvalues[selection.id]
    
    tryCatch({
      uWMW.out["hsa-mir-92"]
      adj.pvalues[match("hsa-mir-92", names(uWMW.out))]
    }, error = function(e) {
      message("hsa-mir-92 not found or could not be subsetted.")
    })
    
    # --- Create a volcano plot to visualize effect sizes and ---
    pdf("volcano_plot.pdf")
    volcanoplot(uWMW.out, add.ref = c("both"), ref.x = c(-log(2),log(2)), 
    ref.y = -log10(0.001))
    dev.off()
    
    # --- Create a forest plot to visualize estimated probabilities ---
    pdf("forest_plot.pdf")
    x.label <- expression("estimated "*P(Y[MNA] < Y[MNSC]))
    forestplot(uWMW.out, estimate = "p", order = selection.id, xlab = x.label) 
    dev.off()
    
    # --- Extract the underlying probabilistic index model ---
    coef(uWMW.out)[1:3]
    vcov(uWMW.out)[1:3,1:3]
    
    # Save outputs to files
    results_df <- uWMW.out[names(uWMW.out), ]
    results_df\$adj.p.value <- adj.pvalues
    write.csv(results_df, "uWMW_results.csv", row.names = TRUE)
    
    write.csv(as.data.frame(coef(uWMW.out)), "uWMW_coefficients.csv", row.names = TRUE)
    write.csv(as.data.frame(vcov(uWMW.out)), "uWMW_vcov.csv", row.names = TRUE)
    saveRDS(uWMW.out, "uWMW_object.rds")

    writeLines(c(
        '"BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION":',
        paste0('    unifiedWMWqPCR: ', as.character(packageVersion('unifiedWMWqPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qpcr_overall_normalization.csv versions.yml
    """
}

workflow BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NBmat, NBgroups ] ]

    main:
    BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION.out.tables
    plots    = BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION.out.plots
    objects  = BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION.out.objects
    versions = BIOC_UNIFIEDWMWQPCR_QPCR_OVERALL_NORMALIZATION.out.versions
}
