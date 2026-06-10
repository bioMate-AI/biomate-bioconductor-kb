#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MPRAnalyze — comparative_analysis
// Identify enhancers that are differentially active between conditions or alleles using a nested GLM and likelihood ratio test.
// Input: dna_counts.tsv, rna_counts.tsv, col_annotations.tsv, controls.txt
// Container: quay.io/biocontainers/bioconductor-mpranalyze:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MPRAnalyze
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] (Optional) Create interaction factors for barcode and condition if performing allelic/mutagenesis comparisons where barcodes are n

nextflow.enable.dsl = 2

process BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
            # Load required library
            library(MPRAnalyze)
            
            # 1. Read User Inputs
            ce.dnaCounts <- as.matrix(read.delim("dna_counts.tsv", header = TRUE, row.names = 1, check.names = FALSE))
            ce.rnaCounts <- as.matrix(read.delim("rna_counts.tsv", header = TRUE, row.names = 1, check.names = FALSE))
            ce.colAnnot <- read.delim("col_annotations.tsv", header = TRUE, row.names = 1, stringsAsFactors = FALSE)
            
            # Robustly read controls.txt as a logical vector
            raw_vals <- trimws(readLines("controls.txt"))
            valid_logicals <- raw_vals %in% c("TRUE", "FALSE", "T", "F", "true", "false", "t", "f")
            if (length(raw_vals) > 0 && !valid_logicals[1]) {
              raw_vals <- raw_vals[-1]
            }
            ce.control <- as.logical(raw_vals)
            
            # 2. Execute Documented Workflow
            obj <- MpraObject(dnaCounts = ce.dnaCounts, rnaCounts = ce.rnaCounts, 
                              dnaAnnot = ce.colAnnot, rnaAnnot = ce.colAnnot, 
                              controls = ce.control)
            
            has_batch <- "batch" %in% colnames(ce.colAnnot)
            lib_factors <- if (has_batch) c("batch", "condition") else "condition"
            
            obj <- estimateDepthFactors(obj, lib.factor = lib_factors,
                                        which.lib = "both")
            
            dna_formula <- if (has_batch) ~ barcode + batch + condition else ~ barcode + condition
            
            obj <- analyzeComparative(obj = obj, 
                                       dnaDesign = dna_formula, 
                                       rnaDesign = ~ condition, 
                                       reducedDesign = ~ 1)
            
            res <- testLrt(obj)
            
            # 3. Save Outputs
            write.csv(res, "comparative_analysis_results.csv", row.names = TRUE)
            saveRDS(obj, "mpra_object.rds")
            
            # Generate and save diagnostic plots
            pdf("comparative_analysis_plots.pdf", width = 10, height = 5)
            par(mfrow = c(1, 2))
            if ("logFC" %in% colnames(res)) {
              plot(density(res\$logFC, na.rm = TRUE), main = "Density of logFC", xlab = "logFC")
              if ("pval" %in% colnames(res)) {
                plot(res\$logFC, -log10(res\$pval), main = "Volcano Plot", xlab = "logFC", ylab = "-log10(pval)")
              }
            } else {
              plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
              text(1, 1, "logFC not available in results")
            }
            dev.off()

    writeLines(c(
        '"BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS":',
        paste0('    MPRAnalyze: ', as.character(packageVersion('MPRAnalyze')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comparative_analysis.csv versions.yml
    """
}

workflow BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dna_counts.tsv, rna_counts.tsv, col_annotations.tsv, controls.txt ] ]

    main:
    BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS.out.tables
    plots    = BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS.out.plots
    objects  = BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS.out.objects
    versions = BIOC_MPRANALYZE_COMPARATIVE_ANALYSIS.out.versions
}
