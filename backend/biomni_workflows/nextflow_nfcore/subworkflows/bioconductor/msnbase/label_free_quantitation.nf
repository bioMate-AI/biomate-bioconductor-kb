#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msnbase — label_free_quantitation
// Perform label-free MS2 quantitation using spectral counting or spectral index (SIn) methods.
// Input: quantFile.mzXML, identFile.mzid
// Container: quay.io/biocontainers/bioconductor-msnbase:2.36.0--r45ha27e39d_0
// R packages: MSnbase
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNBASE_LABEL_FREE_QUANTITATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msnbase:2.36.0--r45ha27e39d_0"

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
    .bm_deps <- c("MSnbase")
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
    library(MSnbase)
    
    # Define input files exactly as specified
    quantFile <- "quantFile.mzXML"
    identFile <- "identFile.mzid"
    
    # Verify input files exist before proceeding
    if (!file.exists(quantFile)) {
      stop(paste("Required input file missing:", quantFile))
    }
    if (!file.exists(identFile)) {
      stop(paste("Required input file missing:", identFile))
    }
    
    # 1. Import raw MS data
    msexp <- readMSData(quantFile, verbose = FALSE)
    
    # 2. Integrate peptide identification data
    msexp <- addIdentificationData(msexp, id = identFile)
    
    # 3. Filter out unidentified spectra
    msexp <- removeNoId(msexp)
    
    # 4. Quantify using spectral counting method
    sc <- quantify(msexp, method = "count")
    
    # 5. Aggregate features to protein level
    sc <- combineFeatures(sc, groupBy = fData(sc)\$DatabaseAccess, method = "sum")
    
    # 6. Quantify using Spectral Index (SIn) method
    siquant <- quantify(msexp, method = "SIn")
    
    # --- Save Outputs ---
    
    # Save the MSnSet objects as RDS files for downstream R analysis
    saveRDS(sc, "spectral_counts_protein.rds")
    saveRDS(siquant, "spectral_index_peptide.rds")
    
    # Export quantitative matrices to CSV files
    write.csv(as.data.frame(exprs(sc)), "spectral_counts_protein.csv", row.names = TRUE)
    write.csv(as.data.frame(exprs(siquant)), "spectral_index_peptide.csv", row.names = TRUE)
    
    # Export feature metadata to CSV files
    write.csv(fData(sc), "protein_metadata.csv", row.names = TRUE)
    write.csv(fData(siquant), "peptide_metadata.csv", row.names = TRUE)
    
    # Generate a summary PDF plot of the quantitation results
    pdf("quantitation_distributions.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Plot Spectral Counts distribution
    if (ncol(sc) > 0 && nrow(sc) > 0) {
      hist(exprs(sc), 
           main = "Protein Spectral Counts", 
           xlab = "Spectral Count (Sum)", 
           col = "skyblue", 
           border = "white")
    } else {
      plot.new()
      text(0.5, 0.5, "No Spectral Count Data to Plot")
    }
    
    # Plot Spectral Index distribution
    if (ncol(siquant) > 0 && nrow(siquant) > 0) {
      hist(log10(exprs(siquant) + 1), 
           main = "Peptide Spectral Index (SIn)", 
           xlab = "log10(SIn + 1)", 
           col = "salmon", 
           border = "white")
    } else {
      plot.new()
      text(0.5, 0.5, "No SIn Data to Plot")
    }
    
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to working directory.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSNBASE_LABEL_FREE_QUANTITATION":
        msnbase: \$(Rscript -e 'cat(as.character(packageVersion("msnbase")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_label_free_quantitation.csv versions.yml
    """
}

workflow BIOC_MSNBASE_LABEL_FREE_QUANTITATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quantFile.mzXML, identFile.mzid ] ]

    main:
    BIOC_MSNBASE_LABEL_FREE_QUANTITATION(ch_input)

    emit:
    tables   = BIOC_MSNBASE_LABEL_FREE_QUANTITATION.out.tables
    plots    = BIOC_MSNBASE_LABEL_FREE_QUANTITATION.out.plots
    objects  = BIOC_MSNBASE_LABEL_FREE_QUANTITATION.out.objects
    versions = BIOC_MSNBASE_LABEL_FREE_QUANTITATION.out.versions
}
