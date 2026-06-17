#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lipidr — lipidomics_analysis_workflow
// Perform a complete downstream lipidomics analysis from Skyline CSV files, including QC, normalization, multivariate analysis, differential expression, and lipid
// Input: data.csv, clin.csv
// Container: quay.io/biocontainers/bioconductor-lipidr:2.24.0--r45hdfd78af_0
// R packages: ggplot2, lipidr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: enrichment plot

nextflow.enable.dsl = 2

process BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-lipidr:2.24.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "lipidr", "SummarizedExperiment")
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
    library(lipidr)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # Verify input files exist in the working directory
    if (!file.exists("data.csv")) {
      stop("Error: 'data.csv' not found in the working directory.")
    }
    if (!file.exists("clin.csv")) {
      stop("Error: 'clin.csv' not found in the working directory.")
    }
    
    # --- Import Skyline CSV files ---
    filelist = "data.csv"
    d = read_skyline(filelist)
    print(d)
    
    # --- Add sample annotations ---
    clinical_file = "clin.csv"
    d = add_sample_annotation(d, clinical_file)
    print(colData(d))
    
    # --- Subset data ---
    d_subset = d[1:10, 1:10]
    print(rowData(d_subset))
    print(colData(d))
    
    d_qc = d[, d\$group == "QC"]
    print(rowData(d_qc))
    print(colData(d_qc))
    
    pc_lipids = rowData(d)\$Class %in% c("PC", "PCO", "PCP")
    d_pc = d[pc_lipids,]
    print(rowData(d_pc))
    print(colData(d_pc))
    
    lipid_classes = rowData(d)\$Class %in% c("Cer", "PC", "LPC")
    groups = d\$BileAcid != "DCA"
    d = d[lipid_classes, groups]
    d_qc = d[, d\$group == "QC"]
    
    # --- Raw data quality checks (saving plots to PDF) ---
    pdf("qc_plots.pdf", width = 10, height = 8)
    
    p1 = plot_samples(d, type = "tic", log = TRUE)
    print(p1)
    
    p2 = plot_molecules(d_qc, "sd", measure = "Retention Time", log = FALSE)
    print(p2)
    
    p3 = plot_molecules(d_qc, "cv", measure = "Area")
    print(p3)
    
    p4 = plot_lipidclass(d, "boxplot")
    print(p4)
    
    # --- Summarize transitions ---
    d_summarized = summarize_transitions(d, method = "average")
    
    # --- Normalize data ---
    d_normalized = normalize_pqn(d_summarized, measure = "Area", exclude = "blank", log = TRUE)
    p5 = plot_samples(d_normalized, "boxplot")
    print(p5)
    
    dev.off()
    
    # Save normalized data object
    saveRDS(d_normalized, "d_normalized.rds")
    
    # --- Multivariate analysis ---
    pdf("mva_plots.pdf", width = 8, height = 6)
    
    mvaresults = mva(d_normalized, measure="Area", method="PCA")
    p6 = plot_mva(mvaresults, color_by="group", components = c(1,2))
    print(p6)
    
    mvaresults = mva(d_normalized, method = "OPLS-DA", group_col = "Diet", groups=c("HighFat", "Normal"))
    p7 = plot_mva(mvaresults, color_by="group")
    print(p7)
    
    dev.off()
    
    # Extract and save top lipids from OPLS-DA
    top_lipids_df = top_lipids(mvaresults, top.n=10)
    write.csv(top_lipids_df, "top_lipids_oplsda.csv", row.names = FALSE)
    saveRDS(mvaresults, "mva_results_oplsda.rds")
    
    # --- Differential expression analysis ---
    de_results = de_analysis(
      data=d_normalized, 
      HighFat_water - NormalDiet_water,
      measure="Area"
    )
    print(head(de_results))
    print(significant_molecules(de_results))
    
    # Save DE results
    write.csv(as.data.frame(de_results), "de_results.csv", row.names = FALSE)
    saveRDS(de_results, "de_results.rds")
    
    pdf("de_plots.pdf", width = 8, height = 6)
    p8 = plot_results_volcano(de_results, show.labels = FALSE)
    print(p8)
    dev.off()
    
    # --- Lipid set enrichment analysis (LSEA) ---
    enrich_results = lsea(de_results, rank.by = "logFC")
    print(significant_lipidsets(enrich_results))
    saveRDS(enrich_results, "enrich_results.rds")
    
    # Save significant lipid sets to a text file
    sink("significant_lipidsets.txt")
    print(significant_lipidsets(enrich_results))
    sink()
    
    pdf("enrichment_plots.pdf", width = 8, height = 6)
    p9 = plot_enrichment(de_results, significant_lipidsets(enrich_results), annotation="class")
    print(p9)
    
    p10 = plot_enrichment(de_results, significant_lipidsets(enrich_results), annotation="unsat")
    print(p10)
    
    p11 = plot_chain_distribution(de_results)
    print(p11)
    dev.off()
    
    # Print session info
    sessionInfo()

    writeLines(c(
        '"BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW":',
        paste0('        lipidr: ', as.character(packageVersion("lipidr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lipidomics_analysis_workflow.csv versions.yml
    """
}

workflow BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.csv, clin.csv ] ]

    main:
    BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW.out.tables
    plots    = BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW.out.plots
    objects  = BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW.out.objects
    versions = BIOC_LIPIDR_LIPIDOMICS_ANALYSIS_WORKFLOW.out.versions
}
