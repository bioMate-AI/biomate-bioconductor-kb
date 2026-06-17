#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowPlots — ternary_plot_pfd
// Create a ternary plot to compare the distribution of polyfunctional degrees (PFD) between groups.
// Input: pfd_data.csv
// Container: quay.io/biocontainers/bioconductor-flowplots:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowPlots, vcd
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare ternary data using makeTernaryData
//  * 2. [Core Analysis] Compute group statistics for the legend using computePFDGroupStatsList
//  * 3. [Core Analysis] Generate legend names using legendPFDStatsGroupNames
//  * 4. [Visualization & Output] Plot using vcd::ternaryplot and add the legend using grid_legend

nextflow.enable.dsl = 2

process BIOC_FLOWPLOTS_TERNARY_PLOT_PFD {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("flowPlots", "vcd")
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
    library(flowPlots)
    library(vcd)
    library(grid)
    
    # Read the user input file
    # Using stringsAsFactors = TRUE to ensure the 'group' column is a factor,
    # which is required for as.numeric(pfdDataSubset\$group) to work correctly.
    pfdDF = read.csv("pfd_data.csv", stringsAsFactors = TRUE)
    
    # 1. Prepare ternary data using makeTernaryData
    # Removed hardcoded subsetting to allow user data with different experimental conditions
    pfdDataSubset = pfdDF
    ternaryData = makeTernaryData(pfdDataSubset, 1, 2, 3:4)
    colnames(ternaryData) = c("PFD1", "PFD2", "PFD3-4")
    
    # 2. Compute group statistics for the legend using computePFDGroupStatsList
    # Dynamically extract group names instead of hardcoding them
    if (is.null(levels(pfdDataSubset\$group))) {
        pfdDataSubset\$group = as.factor(pfdDataSubset\$group)
    }
    groupNames = levels(pfdDataSubset\$group)
    
    groupPFDDataList = lapply(groupNames, function(g) {
        subset(pfdDataSubset, group == g, select = c(PFD1:PFD4))
    })
    
    pfdGroupStatsList = computePFDGroupStatsList(groupPFDDataList, pfdValues=1:4,
       numDigitsMean=3, numDigitsSD=2)
    
    # 3. Generate legend names using legendPFDStatsGroupNames
    legendNames = legendPFDStatsGroupNames(pfdGroupStatsList, groupNames)
    
    # 4. Plot using vcd::ternaryplot and add the legend using grid_legend
    pdf("ternary_plot.pdf", width = 8, height = 8)
    
    # Dynamically generate colors and legend parameters based on the number of groups
    numGroups = length(groupNames)
    groupColors = as.numeric(pfdDataSubset\$group) + 1
    legendColors = seq_len(numGroups) + 1
    legendPch = rep(20, numGroups)
    
    ternaryplot(ternaryData, cex=.5, col=groupColors,  
       main="TERNARY PLOT OF PFD DATA")
    grid_legend(0.8, 0.7, pch=legendPch, col=legendColors, legendNames, 
       title = "Group (n), mean/sd:", gp=gpar(cex=.8))
    dev.off()
    
    # Save meaningful results to output files
    write.csv(ternaryData, "ternary_data.csv", row.names = FALSE)
    saveRDS(pfdGroupStatsList, "pfd_group_stats.rds")

    writeLines(c(
        '"BIOC_FLOWPLOTS_TERNARY_PLOT_PFD":',
        paste0('    flowPlots: ', as.character(packageVersion('flowPlots')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ternary_plot_pfd.csv versions.yml
    """
}

workflow BIOC_FLOWPLOTS_TERNARY_PLOT_PFD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pfd_data.csv ] ]

    main:
    BIOC_FLOWPLOTS_TERNARY_PLOT_PFD(ch_input)

    emit:
    tables   = BIOC_FLOWPLOTS_TERNARY_PLOT_PFD.out.tables
    plots    = BIOC_FLOWPLOTS_TERNARY_PLOT_PFD.out.plots
    objects  = BIOC_FLOWPLOTS_TERNARY_PLOT_PFD.out.objects
    versions = BIOC_FLOWPLOTS_TERNARY_PLOT_PFD.out.versions
}
