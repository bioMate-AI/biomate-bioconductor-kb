#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crlmm — simple_genotyping
// Genotype Affymetrix CEL files quickly using the basic CRLMM algorithm to obtain genotype calls and confidence scores.
// Input: celFiles
// Container: quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0
// R packages: crlmm, hapmapsnp6, oligoClasses
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRLMM_SIMPLE_GENOTYPING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0"

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
    .bm_deps <- c("crlmm", "hapmapsnp6", "oligoClasses")
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
    require(oligoClasses)
    library(crlmm)
    
    # Identify CEL files in the current working directory
    celFiles <- list.celfiles(".", full.names=TRUE)
    
    if (length(celFiles) == 0) {
      stop("Error: No CEL files found in the current working directory. Please provide raw Affymetrix CEL files.")
    }
    
    # Run the crlmm function exactly as documented
    message("Running CRLMM genotyping...")
    system.time(crlmmResult <- crlmm(celFiles, verbose=FALSE))
    
    # Display the documented outputs
    message("Displaying first 10 genotype calls:")
    print(calls(crlmmResult)[1:10, , drop=FALSE])
    
    message("Displaying first 10 confidence scores:")
    print(confs(crlmmResult)[1:10, , drop=FALSE])
    
    message("Displaying Signal-to-Noise Ratio (SNR):")
    print(crlmmResult[["SNR"]])
    
    # Write named output files
    message("Saving results to disk...")
    
    # 1. Save the complete SnpSet object
    saveRDS(crlmmResult, file = "crlmm_result.rds")
    
    # 2. Save genotype calls to CSV
    write.csv(calls(crlmmResult), file = "genotype_calls.csv", row.names = TRUE)
    
    # 3. Save confidence scores to CSV
    write.csv(confs(crlmmResult), file = "confidence_scores.csv", row.names = TRUE)
    
    # 4. Save SNR values to CSV
    snr_df <- data.frame(
      Sample = names(crlmmResult[["SNR"]]),
      SNR = crlmmResult[["SNR"]],
      stringsAsFactors = FALSE
    )
    write.csv(snr_df, file = "snr_values.csv", row.names = FALSE)
    
    # 5. Generate a PDF plot of SNR values
    pdf("snr_histogram.pdf", width = 6, height = 6)
    hist(crlmmResult[["SNR"]], 
         main = "Signal-to-Noise Ratio (SNR) Distribution", 
         xlab = "SNR", 
         col = "skyblue", 
         border = "white")
    abline(v = 5, col = "red", lty = 2, lwd = 2) # Threshold for poor quality
    legend("topright", legend = "Quality Threshold (SNR = 5)", col = "red", lty = 2, lwd = 2)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: crlmm_result.rds, genotype_calls.csv, confidence_scores.csv, snr_values.csv, snr_histogram.pdf")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CRLMM_SIMPLE_GENOTYPING":
        crlmm: \$(Rscript -e 'cat(as.character(packageVersion("crlmm")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simple_genotyping.csv versions.yml
    """
}

workflow BIOC_CRLMM_SIMPLE_GENOTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celFiles ] ]

    main:
    BIOC_CRLMM_SIMPLE_GENOTYPING(ch_input)

    emit:
    tables   = BIOC_CRLMM_SIMPLE_GENOTYPING.out.tables
    plots    = BIOC_CRLMM_SIMPLE_GENOTYPING.out.plots
    objects  = BIOC_CRLMM_SIMPLE_GENOTYPING.out.objects
    versions = BIOC_CRLMM_SIMPLE_GENOTYPING.out.versions
}
