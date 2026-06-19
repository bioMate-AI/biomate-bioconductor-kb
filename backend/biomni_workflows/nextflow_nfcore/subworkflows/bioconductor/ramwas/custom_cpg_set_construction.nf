#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ramwas — custom_cpg_set_construction
// Construct a custom CpG set from a reference genome, inject common SNPs filtered by minor allele frequency, and perform an in silico alignment experiment to filt
// Input: count_ALL_chr22.txt, bams/
// Container: quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, ramwas
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "ramwas")
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
    library(ramwas)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Set reference genome
    BSGenome = Hsapiens
    
    # --- Inject common SNPs (MAF > 0.01) into the reference genome ---
    message("Injecting SNPs into chr22...")
    genome = list()
    genome[["chr22"]] = injectSNPsMAF(
      gensequence = BSGenome[["chr22"]],
      frqcount = "count_ALL_chr22.txt",
      MAF = 0.01
    )
    
    # --- Identify all potential CpG sites in the SNP-injected ---
    message("Identifying potential CpG sites...")
    cpgset = getCpGsetALL(genome)
    
    # Save the initial CpG set to an RDS file as required by ramwasParameters
    filecpgset = "cpgset_initial.rds"
    saveRDS(cpgset, file = filecpgset)
    
    # --- Generate artificial FASTQ reads from the reference genome ---
    message("Generating in silico FASTQ reads...")
    insilicoFASTQ(
      con = "chr1.fastq.gz",
      gensequence = BSGenome[["chr1"]],
      fraglength = 75
    )
    
    # Define parameters for scanning the simulated BAM files
    targetcov = 75
    covtolerance = 10
    
    # Dynamically detect BAM files in the user-provided bams/ directory
    bam_files = list.files("bams", pattern = "\\\\.bam\$")
    if (length(bam_files) == 0) {
      stop("Error: No BAM files found in the 'bams/' directory.")
    }
    chrset = gsub("\\\\.bam\$", "", bam_files)
    
    # --- Define parameters for scanning the simulated BAM files ---
    message("Setting up RaMWAS parameters...")
    param = ramwasParameters(
      dirproject = ".",
      dirbam = "./bams",
      dirfilter = TRUE,
      bamnames = chrset,
      bam2sample = list(all_samples = chrset),
      scoretag = "AS",
      minscore = 100,
      minfragmentsize = targetcov,
      maxfragmentsize = targetcov,
      minavgcpgcoverage = 0,
      minnonzerosamples = 0,
      filecpgset = filecpgset
    )
    
    # Preprocess parameters
    param1 = parameterPreprocess(param)
    
    # --- Scan the simulated BAMs and calculate normalized coverage ---
    message("Scanning BAM files...")
    ramwas1scanBams(param)
    
    message("Calculating normalized coverage...")
    ramwas3normalizedCoverage(param)
    
    # --- Filter the CpG set by keeping only the sites that fall ---
    message("Filtering CpG set by in silico coverage...")
    # Preprocess parameters to learn the location of coverage matrix
    param1 = parameterPreprocess(param)
    
    # Load the coverage matrix (vector)
    cover = fm.load(paste0(param1\$dircoveragenorm, "/Coverage"))
    
    # Split the coverage by chromosomes
    fac = rep(seq_along(cpgset), times = sapply(cpgset, length))
    levels(fac) = names(cpgset)
    class(fac) = "factor"
    cover = split(cover, fac)
    
    # Filter CpGs on each chromosome by the coverage
    cpgsetQC = cpgset
    for (i in seq_along(cpgset)) {
      keep = (cover[[i]] >= (targetcov - covtolerance)) & (cover[[i]] <= (targetcov + covtolerance))
      cpgsetQC[[i]] = cpgset[[i]][keep]
    }
    
    # Save the final QC-filtered CpG set
    output_rds = "My_cpgset_QC.rds"
    saveRDS(file = output_rds, object = cpgsetQC)
    message("Saved QC-filtered CpG set to: ", output_rds)
    
    # Write a summary of the filtering process
    summary_df = data.frame(
      Chromosome = names(cpgset),
      Original_CpGs = sapply(cpgset, length),
      Filtered_CpGs = sapply(cpgsetQC, length)
    )
    write.csv(summary_df, "cpg_filtering_summary.csv", row.names = FALSE)
    message("Saved filtering summary to: cpg_filtering_summary.csv")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION":',
        paste0('        ramwas: ', as.character(packageVersion("ramwas")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_cpg_set_construction.csv versions.yml
    """
}

workflow BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_ALL_chr22.txt, bams/ ] ]

    main:
    BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.tables
    plots    = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.plots
    objects  = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.objects
    versions = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.versions
}
