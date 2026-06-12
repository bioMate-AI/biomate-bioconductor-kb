#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dexseq — python_htseq_workflow
// Perform differential exon usage analysis starting from pre-calculated HTSeq count files and a flattened GFF file.
// Input: count_files, flattened.gff, sample_table.csv
// Container: quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0
// R packages: DEXSeq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0"

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
    .bm_deps <- c("DEXSeq")
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
    library(DEXSeq)
    
    # --- Define paths to count files and the flattened GFF file ---
    flattenedFile = "flattened.gff"
    
    # --- Create a sample metadata data frame ---
    # Read the sample metadata table from the working directory
    sampleTable = read.csv("sample_table.csv", row.names = 1, stringsAsFactors = TRUE)
    
    # Resolve and align the count files with the rows of the sample table
    all_files = list.files(".", full.names = TRUE)
    countFiles = sapply(rownames(sampleTable), function(sn) {
      match_file = all_files[grep(sn, basename(all_files))]
      if (length(match_file) > 0) {
        return(match_file[1])
      } else {
        # Fallback to sample_name.txt in the current directory if no direct match is found
        return(file.path(".", paste0(sn, ".txt")))
      }
    })
    
    # --- Build a DEXSeqDataSet using DEXSeqDataSetFromHTSeq() ---
    dxd = DEXSeqDataSetFromHTSeq(
       countFiles,
       sampleData=sampleTable,
       design= ~ sample + exon + condition:exon,
       flattenedfile=flattenedFile )
    
    # --- Run the complete analysis using the wrapper function ---
    dxr = DEXSeq(dxd)
    
    # Save meaningful results to output files
    # Save the DEXSeqResults and DEXSeqDataSet objects as RDS files
    saveRDS(dxd, "dexseq_dataset.rds")
    saveRDS(dxr, "dexseq_results.rds")
    
    # Export the results table to a CSV file
    dxr_df = as.data.frame(dxr)
    write.csv(dxr_df, "dexseq_results.csv", row.names = TRUE)
    
    # Generate diagnostic and visualization plots
    # 1. Dispersion estimation plot
    pdf("dispersion_plot.pdf")
    plotDispEsts(dxd)
    dev.off()
    
    # 2. MA plot (Mean expression vs log2 fold change)
    pdf("ma_plot.pdf")
    plotMA(dxr, cex = 0.8)
    dev.off()
    
    # 3. Expression plot for the top significant gene (or first gene if none are significant)
    sig_exons = dxr[which(dxr\$padj < 0.1), ]
    if (nrow(sig_exons) > 0) {
      top_gene = sig_exons\$groupID[1]
    } else {
      top_gene = dxr\$groupID[1]
    }
    
    if (!is.na(top_gene)) {
      pdf("top_gene_dexseq_plot.pdf", width = 12, height = 8)
      plotDEXSeq(dxr, top_gene, legend = TRUE, cex.axis = 1.2, cex = 1.3, lwd = 2)
      dev.off()
    }

    writeLines(c(
        '"BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW":',
        paste0('        dexseq: ', as.character(packageVersion("dexseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_python_htseq_workflow.csv versions.yml
    """
}

workflow BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_files, flattened.gff, sample_table.csv ] ]

    main:
    BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.tables
    plots    = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.plots
    objects  = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.objects
    versions = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.versions
}
