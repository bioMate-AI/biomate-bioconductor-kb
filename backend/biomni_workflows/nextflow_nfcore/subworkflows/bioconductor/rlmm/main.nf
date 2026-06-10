#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RLMM — affymetrix_xba_genotyping
// Normalize raw probe intensities, estimate theta values, classify genotypes, and plot allele summaries for Affymetrix 100K-Xba SNP arrays.
// Input: Xba.CQV, Xba.regions, snps.lst, .raw files
// Container: quay.io/biocontainers/bioconductor-rlmm:1.72.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RLMM
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the RLMM library
//  * 2. [Core Analysis] Normalize raw probe intensity files using normalize_Rawfiles
//  * 3. [Core Analysis] Estimate theta A and theta B values using create_Thetafile
//  * 4. [Core Analysis] Classify genotypes using Classify with Mahalanobis distance
//  * 5. [Visualization & Output] Plot allele summaries for specific SNPs using plot_theta

nextflow.enable.dsl = 2

process BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        
        # Check for required input files in the working directory
        required_files <- c("Xba.CQV", "Xba.regions", "snps.lst")
        missing_files <- required_files[!file.exists(required_files)]
        raw_files <- list.files(pattern = "\\\\.raw\$")
        
        if (length(missing_files) > 0 || length(raw_files) == 0) {
          stop(paste(
            "Error: Missing required input files in the working directory.\n",
            "Required files: Xba.CQV, Xba.regions, snps.lst, and at least one .raw file.\n",
            "Missing standard files:", paste(missing_files, collapse = ", "), "\n",
            "Number of .raw files found:", length(raw_files)
          ))
        }
        
        # 1. Load the RLMM library
        library(RLMM)
        
        # 2. Normalize raw probe intensity files using normalize_Rawfiles
        message("Step 1: Normalizing raw probe intensity files...")
        normalize_Rawfiles(cqvfile="Xba.CQV")
        
        # 3. Estimate theta A and theta B values using create_Thetafile
        message("Step 2: Estimating theta values...")
        create_Thetafile(start=1, end=-1, thetafile="Xba.theta")
        
        # 4. Classify genotypes using Classify with Mahalanobis distance
        message("Step 3: Classifying genotypes...")
        Classify(genotypefile="Xba.rlmm",regionsfile="Xba.regions",thetafile="Xba.theta")
        
        # Read and display the classification results
        message("Step 4: Reading classification results...")
        x<-read.table("Xba.rlmm")
        print(x[1:2,1:5])
        
        # Save the results to output files (CSV and RDS)
        write.csv(x, file = "Xba_genotypes.csv", row.names = FALSE)
        saveRDS(x, file = "Xba_genotypes.rds")
        
        # 5. Plot allele summaries for specific SNPs using plot_theta
        # We wrap the onscreen plot in a PDF device to save it as a named output file
        message("Step 5: Plotting allele summaries...")
        pdf("allele_summary_plots.pdf", width = 7, height = 7)
        plot_theta(genotypefile="Xba.rlmm",thetafile="Xba.theta",plotfile="",snpsfile="snps.lst")
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to 'Xba_genotypes.csv', 'Xba_genotypes.rds', and 'allele_summary_plots.pdf'.")

    writeLines(c(
        '"BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING":',
        paste0('    RLMM: ', as.character(packageVersion('RLMM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affymetrix_xba_genotyping.csv versions.yml
    """
}

workflow BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Xba.CQV, Xba.regions, snps.lst, .raw files ] ]

    main:
    BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING(ch_input)

    emit:
    tables   = BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING.out.tables
    plots    = BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING.out.plots
    objects  = BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING.out.objects
    versions = BIOC_RLMM_AFFYMETRIX_XBA_GENOTYPING.out.versions
}
