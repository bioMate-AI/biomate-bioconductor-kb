#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: magar — meth_qtl_with_imputation
// Import raw IDAT files, perform genotype calling and imputation via the Michigan Imputation Server, and call methQTLs.
// Input: idat_dir, geno_dir, sample_annotation.tsv
// Container: quay.io/biocontainers/bioconductor-magar:1.18.0--r45hdfd78af_0
// R packages: MAGAR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_MAGAR_METH_QTL_WITH_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-magar:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("MAGAR")
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
    
    # Load required library
    library(MAGAR)
    
    # Input validation
    idat.dir <- "idat_dir"
    geno.dir <- "geno_dir"
    anno.sheet <- "sample_annotation.tsv"
    
    if (!dir.exists(idat.dir)) {
      stop(paste("Error: Methylation IDAT directory not found at:", idat.dir))
    }
    if (!dir.exists(geno.dir)) {
      stop(paste("Error: Genotyping IDAT directory not found at:", geno.dir))
    }
    if (!file.exists(anno.sheet)) {
      stop(paste("Error: Sample annotation file not found at:", anno.sheet))
    }
    
    # --- Configure imputation options ---
    qtlSetOption(
      impute.geno.data=TRUE,
      imputation.reference.panel="apps@hrc-r1.1",
      imputation.phasing.method="shapeit",
      imputation.population="eur"
    )
    
    # --- Import and impute data using doImport ---
    qtlSetOption(hdf5dump=TRUE)
    imp.data <- doImport(data.location = c(idat.dir=idat.dir,geno.dir=geno.dir),
                        s.anno = anno.sheet,
                        s.id.col = "ID",
                        tab.sep = "\t",
                        out.folder = getwd())
    
    # Save imported data object
    saveRDS(imp.data, file = "imported_meth_qtl_data.rds")
    
    # --- Call methQTLs using doMethQTL ---
    qtlSetOption(standard.deviation.gauss=100,
        cluster.cor.threshold=0.75)
    meth.qtl.res <- doMethQTL(imp.data,default.options=FALSE,p.val.cutoff=0.05)
    
    # Save methQTL result object
    saveRDS(meth.qtl.res, file = "meth_qtl_result_object.rds")
    
    # --- Extract results using getResult ---
    result.table <- getResult(meth.qtl.res)
    
    # Write output table
    write.table(result.table, file = "meth_qtl_results.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # Generate downstream visualization plots if results are available
    tryCatch({
      if (nrow(result.table) > 0) {
        pdf("meth_qtl_plots.pdf", width = 8, height = 6)
        
        # Plot distance scatterplot
        print(qtlDistanceScatterplot(meth.qtl.res))
        
        # Plot top SNP-CpG interaction
        sorted.results <- result.table[order(result.table\$P.value, decreasing=FALSE), ]
        print(qtlPlotSNPCpGInteraction(imp.data, sorted.results\$CpG[1], sorted.results\$SNP[1]))
        
        dev.off()
        message("Plots successfully saved to 'meth_qtl_plots.pdf'")
      } else {
        message("No significant methQTLs found to plot.")
      }
    }, error = function(e) {
      warning("Could not generate downstream plots: ", e\$message)
    })
    
    message("Pipeline completed successfully. Results saved to 'meth_qtl_results.tsv'.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MAGAR_METH_QTL_WITH_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MAGAR_METH_QTL_WITH_IMPUTATION":',
        paste0('        magar: ', as.character(packageVersion("magar")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meth_qtl_with_imputation.csv versions.yml
    """
}

workflow BIOC_MAGAR_METH_QTL_WITH_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ idat_dir, geno_dir, sample_annotation.tsv ] ]

    main:
    BIOC_MAGAR_METH_QTL_WITH_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_MAGAR_METH_QTL_WITH_IMPUTATION.out.tables
    plots    = BIOC_MAGAR_METH_QTL_WITH_IMPUTATION.out.plots
    objects  = BIOC_MAGAR_METH_QTL_WITH_IMPUTATION.out.objects
    versions = BIOC_MAGAR_METH_QTL_WITH_IMPUTATION.out.versions
}
