#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: blacksheepr — piecewise_outlier_analysis
// Perform step-by-step outlier analysis and generate custom heatmaps without using the high-level deva wrapper.
// Input: phosphotable.csv, comptable.csv
// Container: quay.io/biocontainers/bioconductor-blacksheepr:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, blacksheepr
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create sample subgroups from the annotation table using comparison_groupings
//  * 2. [Core Analysis] Convert the continuous count table into a binary outlier table using make_outlier_table
//  * 3. [Core Analysis] Tabulate outliers and aggregate subfeatures to primary features using count_outliers
//  * 4. [Core Analysis] Run the statistical outlier enrichment analysis using outlier_analysis
//  * 5. [Visualization & Output] Order the annotation table and plot results using outlier_heatmap

nextflow.enable.dsl = 2

process BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    
    library(blacksheepr)
    
    # Read user input files from the working directory
    comptable <- read.csv("comptable.csv", row.names = 1, check.names = FALSE)
    phosphotable <- read.csv("phosphotable.csv", row.names = 1, check.names = FALSE)
    
    # 1. Create sample subgroups from the annotation table
    groupings <- comparison_groupings(comptable)
    
    # 2. Convert the continuous count table into a binary outlier table
    reftable_function_out <- make_outlier_table(phosphotable,
                                            analyze_negative_outliers = FALSE)
    outliertab <- reftable_function_out\$outliertab
    upperboundtab <- reftable_function_out\$upperboundtab
    sampmedtab <- reftable_function_out\$sampmedtab
    
    # 3. Tabulate outliers and aggregate subfeatures to primary features
    count_outliers_out <- count_outliers(groupings, outliertab, 
                            aggregate_features = TRUE, feature_delineator = "-")
    grouptablist <- count_outliers_out\$grouptablist
    aggoutliertab <- count_outliers_out\$aggoutliertab
    fractiontab <- count_outliers_out\$fractiontab
    
    # 4. Run the statistical outlier enrichment analysis
    outlier_analysis_out <- outlier_analysis(grouptablist = grouptablist,
                                            fraction_table = fractiontab,
                                            fraction_samples_cutoff = 0.3)
    
    # 5. Order the annotation table and plot results using outlier_heatmap
    plottable <- comptable[do.call(order, c(decreasing = TRUE, 
                                data.frame(comptable[,1:ncol(comptable)]))),]
    hm1 <- outlier_heatmap(outlier_analysis_out = outlier_analysis_out, 
                    counttab = fractiontab, metatable = plottable, 
                    fdrcutoffvalue = 0.1)
    
    # Attempt to print the specific documented heatmap if it exists in the output
    try(hm1\$print_outlieranalysis_for_PAM50_Her2__Her2_vs_PAM50_Her2__not_Her2, silent = TRUE)
    
    # Write output tables to CSV
    write.csv(outliertab, "outliertab.csv", row.names = TRUE)
    write.csv(upperboundtab, "upperboundtab.csv", row.names = TRUE)
    write.csv(sampmedtab, "sampmedtab.csv", row.names = TRUE)
    write.csv(aggoutliertab, "aggoutliertab.csv", row.names = TRUE)
    write.csv(fractiontab, "fractiontab.csv", row.names = TRUE)
    
    # Save individual outlier analysis tables
    for (name in names(outlier_analysis_out)) {
      write.csv(outlier_analysis_out[[name]], paste0(name, ".csv"), row.names = TRUE)
    }
    
    # Save generated heatmaps to a PDF file
    if (!is.null(hm1) && length(hm1) > 0) {
      pdf("outlier_heatmaps.pdf")
      for (name in names(hm1)) {
        try(ComplexHeatmap::draw(hm1[[name]]), silent = TRUE)
      }
      dev.off()
    }
    
    # Save the key R objects for downstream analysis
    saveRDS(outlier_analysis_out, "outlier_analysis_out.rds")
    saveRDS(hm1, "heatmaps.rds")

    writeLines(c(
        '"BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS":',
        paste0('    blacksheepr: ', as.character(packageVersion('blacksheepr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_piecewise_outlier_analysis.csv versions.yml
    """
}

workflow BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phosphotable.csv, comptable.csv ] ]

    main:
    BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS.out.tables
    plots    = BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS.out.plots
    objects  = BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS.out.objects
    versions = BIOC_BLACKSHEEPR_PIECEWISE_OUTLIER_ANALYSIS.out.versions
}
