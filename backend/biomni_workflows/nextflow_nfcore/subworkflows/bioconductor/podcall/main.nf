#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: podcall — ddpcr_methylation_analysis
// Run the complete PoDCall workflow to read raw ddPCR amplitude data, set thresholds, calculate concentrations, and visualize results.
// Input: amplitude_files.csv, Sample_names.csv
// Container: quay.io/biocontainers/bioconductor-podcall:1.18.0--r45hdfd78af_0
// R packages: PoDCall
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-podcall:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("PoDCall")
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
    
    # Load the required library
    library(PoDCall)
    
    # Set seed for reproducibility as threshold setting includes random sampling of droplets
    set.seed(123)
    
    # Define the input directory (working directory)
    path <- "."
    
    # ----------------------------------------------------------------------
    # Stage 1: Run the full PoDCall workflow in one step
    # ----------------------------------------------------------------------
    thresholdTable_ddpcr <- podcallDdpcr(dataDirectory=path,
                                         software="QuantaSoft")
    
    # Save the one-step workflow results
    write.csv(thresholdTable_ddpcr, "podcall_ddpcr_results.csv", row.names=TRUE)
    
    
    # ----------------------------------------------------------------------
    # Stage 2: Run the step-by-step workflow
    # ----------------------------------------------------------------------
    
    # 1. Import raw amplitude data from the directory
    dataList <- importAmplitudeData(dataDirectory=path, skipLines=0)
    ampData <- dataList
    
    # Extract well IDs from the imported amplitude data
    well_id <- names(ampData)
    
    # 2. Import sample sheet information
    sampleSheet <- importSampleSheet(sampleSheet="Sample_names.csv", 
                                     well_id=well_id,
                                     software="QuantaSoft")
    
    # 3. Calculate thresholds, positive droplet counts, and concentrations
    thresholdTable <- podcallThresholds(plateData=ampData)
    
    
    # ----------------------------------------------------------------------
    # Stage 3: Visualize results and save plots to PDF
    # ----------------------------------------------------------------------
    
    # Select channel and well to plot (using the first well in the list)
    ch <- 1 # target channel
    well_id_single <- names(ampData)[1]
    
    # Plot title
    plotTitle <- paste0(well_id_single, ", Ch", ch)
    
    # Open PDF device to save the plots
    pdf("podcall_analysis_plots.pdf", width=11, height=8.5)
    
    # Generate individual channel plot (scatter plot + histogram combined)
    podcallChannelPlot(channelData=ampData[[well_id_single]][,ch],
                        thr=thresholdTable[well_id_single, "thr_target"],
                        channel=ch,
                        plotId=plotTitle)
    
    # Generate individual scatter plot
    podcallScatterplot(channelData=ampData[[well_id_single]][,ch],
                        thr=thresholdTable[well_id_single, "thr_target"],
                        channel=ch,
                        plotId=plotTitle)
    
    # Generate individual histogram
    podcallHistogram(channelData=ampData[[well_id_single]][,ch],
                    thr=thresholdTable[well_id_single, "thr_target"],
                    channel=ch,
                    plotId=plotTitle)
    
    # Generate multiplot comparison across all wells
    ch_multi <- "target"
    podcallMultiplot(plateData=ampData,
                    thresholds=thresholdTable[names(ampData),], 
                    channel=ch_multi, colCh=1)
    
    # Close the PDF device
    dev.off()
    
    
    # ----------------------------------------------------------------------
    # Stage 4: Write output files
    # ----------------------------------------------------------------------
    write.csv(thresholdTable, "threshold_table.csv", row.names=TRUE)
    write.csv(sampleSheet, "imported_sample_sheet.csv", row.names=FALSE)
    saveRDS(thresholdTable, "threshold_table.rds")
    saveRDS(ampData, "amplitude_data.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS":
        podcall: \$(Rscript -e 'cat(as.character(packageVersion("podcall")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ddpcr_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ amplitude_files.csv, Sample_names.csv ] ]

    main:
    BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_PODCALL_DDPCR_METHYLATION_ANALYSIS.out.versions
}
