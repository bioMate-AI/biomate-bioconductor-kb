#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ramwas — standard_mwas_pipeline
// Perform a complete MWAS workflow from raw BAM files, including QC, normalization, PCA, association testing, annotation, and cross-validated risk score predictio
// Input: bams/, bam_list.txt, Simulated_chromosome.rds, covariates.txt
// Container: quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0
// R packages: filematrix, knitr, pander, ramwas
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAMWAS_STANDARD_MWAS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0"

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
    .bm_deps <- c("filematrix", "knitr", "pander", "ramwas")
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
    library(ramwas)
    library(filematrix)
    
    # Define project directory
    dr = "ramwas_project"
    if (!dir.exists(dr)) {
      dir.create(dr, recursive = TRUE)
    }
    
    # --- Define pipeline parameters using ramwasParameters ---
    param = ramwasParameters(
     dirproject = dr,
     dirbam = "bams",
     filebamlist = "bam_list.txt",
     filecpgset = "Simulated_chromosome.rds",
     cputhreads = 2,
     scoretag = "MAPQ",
     minscore = 4,
     minfragmentsize = 50,
     maxfragmentsize = 250,
     minavgcpgcoverage = 0.3,
     minnonzerosamples = 0.3,
     filecovariates = "covariates.txt",
     modelcovariates = NULL,
     modeloutcome = "age",
     modelPCs = 0,
     toppvthreshold = 1e-5,
     bihost = "grch37.ensembl.org",
     bimart = "ENSEMBL_MART_ENSEMBL",
     bidataset = "hsapiens_gene_ensembl",
     biattributes = c("hgnc_symbol","entrezgene","strand"),
     bifilters = list(with_hgnc_trans_name = TRUE),
     biflank = 0,
     cvnfolds = 5,
     mmalpha = 0,
     mmncpgs = c(5, 10, 50, 100, 500, 1000, 2000)
    )
    
    # Preprocess parameters to resolve paths
    pfull = parameterPreprocess(param)
    
    # --- Scan BAM files and calculate QC metrics ---
    message("Step 1: Scanning BAM files...")
    ramwas1scanBams(param)
    
    # --- Summarize QC metrics and estimate fragment size ---
    message("Step 2: Collecting QC metrics...")
    ramwas2collectqc(param)
    
    # --- Calculate and normalize the CpG score (coverage) matrix ---
    message("Step 3: Calculating normalized coverage...")
    ramwas3normalizedCoverage(param)
    
    # --- Perform Principal Component Analysis (PCA) ---
    message("Step 4: Performing PCA...")
    ramwas4PCA(param)
    
    # --- Run the association analysis (MWAS) ---
    message("Step 5: Running MWAS...")
    ramwas5MWAS(param)
    
    # --- Annotate top findings with gene symbols and IDs ---
    message("Step 6: Annotating top findings...")
    tryCatch({
      ramwas6annotateTopFindings(param)
    }, error = function(e) {
      warning("Annotation step failed (possibly due to biomaRt network issues): ", e\$message)
    })
    
    # --- Predict the outcome variable using cross-validated ---
    message("Step 7: Running cross-validated risk score prediction...")
    ramwas7riskScoreCV(param)
    
    
    # ==========================================
    # EXPORT MEANINGFUL RESULTS AND PLOTS
    # ==========================================
    message("Exporting results and generating summary plots...")
    
    # 1. Export QC Summary Table
    qc_file = file.path(pfull\$dirqc, "summary_total", "Summary_QC_R.txt")
    if (file.exists(qc_file)) {
      qc_data = read.table(qc_file, header = TRUE, sep = "\t")
      write.csv(qc_data, "QC_Summary.csv", row.names = FALSE)
    }
    
    # 2. Export PCA Eigenvalues
    eigenvalues_path = file.path(pfull\$dirpca, "eigenvalues")
    if (file.exists(paste0(eigenvalues_path, ".bmd"))) {
      eigenvalues = fm.load(eigenvalues_path)
      write.csv(data.frame(PC = seq_along(eigenvalues), Eigenvalue = eigenvalues), "PCA_Eigenvalues.csv", row.names = FALSE)
    }
    
    # 3. Export MWAS Top Findings
    mwas_top_file = file.path(pfull\$dirmwas, "Top_tests.txt")
    if (file.exists(mwas_top_file)) {
      mwas_top = read.table(mwas_top_file, header = TRUE, sep = "\t")
      write.csv(mwas_top, "MWAS_Top_Findings.csv", row.names = FALSE)
    }
    
    # 4. Plot Fragment Size Distribution Estimate
    pdf("QC_Fragment_Size_Distribution.pdf", width = 7, height = 7)
    frag_file = file.path(pfull\$dirproject, "Fragment_size_distribution.txt")
    qc_rds = file.path(pfull\$dirqc, "summary_total", "qclist.rds")
    if (file.exists(frag_file) && file.exists(qc_rds)) {
      qc_data = readRDS(qc_rds)
      frdata = qc_data\$total\$hist.isolated.dist1
      estimate = as.double(readLines(frag_file))
      plotFragmentSizeDistributionEstimate(frdata, estimate)
    }
    dev.off()
    
    # 5. Plot PCA Scree Plot
    pdf("PCA_Scree_Plot.pdf", width = 7, height = 7)
    if (file.exists(paste0(eigenvalues_path, ".bmd"))) {
      plotPCvalues(eigenvalues)
    }
    dev.off()
    
    # 6. Plot MWAS QQ and Manhattan Plots
    pdf("MWAS_QQ_and_Manhattan_Plots.pdf", width = 12, height = 6)
    stats_path = file.path(pfull\$dirmwas, "Stats_and_pvalues")
    if (file.exists(paste0(stats_path, ".bmd"))) {
      mwas = getMWASandLocations(param)
      layout(matrix(c(1, 2), 1, 2, byrow = TRUE), widths = c(1, 2.2))
      qqPlotFast(mwas\$`p-value`)
      man = manPlotPrepare(
        pvalues = mwas\$`p-value`,
        chr = mwas\$chr,
        pos = mwas\$start,
        chrmargins = 0
      )
      manPlotFast(man)
    }
    dev.off()
    
    # 7. Plot Cross-Validation Prediction Success
    pdf("CV_Prediction_Plot.pdf", width = 7, height = 7)
    rds_dir = file.path(pfull\$dircv, "rds")
    if (dir.exists(rds_dir)) {
      rds_files = list.files(rds_dir, pattern = "^CpGs=.*\\\\.rds\$", full.names = TRUE)
      if (length(rds_files) > 0) {
        cv = readRDS(rds_files[1])
        cpgs_match = regmatches(basename(rds_files[1]), regexpr("[0-9]+", basename(rds_files[1])))
        cpgs_val = if (length(cpgs_match) > 0) as.integer(cpgs_match) else 50
        plotPrediction(
          param = pfull,
          outcome = cv\$outcome,
          forecast = cv\$forecast,
          cpgs2use = cpgs_val,
          main = "Prediction success (EN on coverage)"
        )
      }
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RAMWAS_STANDARD_MWAS_PIPELINE":',
        paste0('        ramwas: ', as.character(packageVersion("ramwas")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_mwas_pipeline.csv versions.yml
    """
}

workflow BIOC_RAMWAS_STANDARD_MWAS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bams/, bam_list.txt, Simulated_chromosome.rds, covariates.txt ] ]

    main:
    BIOC_RAMWAS_STANDARD_MWAS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RAMWAS_STANDARD_MWAS_PIPELINE.out.tables
    plots    = BIOC_RAMWAS_STANDARD_MWAS_PIPELINE.out.plots
    objects  = BIOC_RAMWAS_STANDARD_MWAS_PIPELINE.out.objects
    versions = BIOC_RAMWAS_STANDARD_MWAS_PIPELINE.out.versions
}
