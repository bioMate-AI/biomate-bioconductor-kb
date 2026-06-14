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
