#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowViz — two_dimensional_scatter_plots
// Visualize flow cytometry data in 2D scatter plots with geometric or data-driven gates.
// Input: GvHD
// Container: quay.io/biocontainers/bioconductor-flowviz:1.74.0--r45hdfd78af_0
// R packages: flowCore, flowStats, flowViz
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowStats, flowViz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subset the flowSet to the patient of interest
//  * 2. [Core Analysis] Transform fluorescence channels using asinh
//  * 3. [Input & Preparation] Define geometric gates (rectangleGate) or data-driven gates (norm2Filter, curv2Filter)
//  * 4. [Visualization & Output] Plot using xyplot with the filter argument (smoothed, non-smoothed, hexbin, or with statistics)

nextflow.enable.dsl = 2

process BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS {
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
    .bm_deps <- c("flowCore", "flowStats", "flowViz")
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
    library(flowCore)
    library(flowViz)
    library(flowStats)
    
    # Read the user input flowSet object from the working directory
    GvHD <- readRDS("GvHD.rds")
    
    # Open PDF device to save the plots
    pdf("flowViz_plots.pdf", width=10, height=8)
    
    # 1. Subset the flowSet to the patient of interest
    GvHD <- GvHD[pData(GvHD)\$Patient==6]
    
    # 2. Transform fluorescence channels using asinh
    tf <- transformList(from=colnames(GvHD)[3:7], tfun=asinh)
    GvHD <- tf %on% GvHD
    
    # 3. Define geometric gates (rectangleGate) and plot
    rgate <- rectangleGate("FSC-H"=c(0, 400),"SSC-H"=c(-50, 300))
    print(xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate))
    
    rgate2 <- rgate * rectangleGate("FL1-H"=c(2, 4))
    print(xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate2))
    
    # Non-smoothed scatter plots
    print(xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate, smooth=FALSE))
    
    # Hexbin scatter plot for faster rendering
    print(xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate, smooth=FALSE, xbin=128))
    
    # Non-smoothed plot with statistics
    print(xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate, smooth=FALSE, stat=TRUE, pos=0.5, abs=TRUE))
    
    # Multiple filters in one panel
    recGate1<-rectangleGate("FL4-H"=c(3.3,5.3),"FL2-H"=c(2.5,5))
    recGate2<-rectangleGate("FL4-H"=c(4,6),"FL2-H"=c(6,8))
    filters1<-filters(list(recGate1,recGate2))
    print(xyplot(`FL2-H` ~ `FL4-H` ,data=GvHD[[1]] ,filter=filters1 ,stat=TRUE ,margin=FALSE ))
    
    # 4. Data-driven gates (norm2Filter)
    n2Filter <- norm2Filter("SSC-H", "FSC-H", scale=2, filterId="Lymphocytes")
    n2Filter.results <- filter(GvHD, n2Filter)
    print(xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=n2Filter.results))
    
    # Data-driven gates (curv2Filter)
    c2f <- curv2Filter("FSC-H", "FL4-H", bwFac=1.8)
    c2f.results <- filter(GvHD, c2f)
    print(xyplot(`FL4-H` ~ `FSC-H` | Visit, data=GvHD, filter=c2f.results))
    
    # Close the PDF device
    dev.off()
    
    # Save the filter results to RDS files
    saveRDS(n2Filter.results, "n2Filter_results.rds")
    saveRDS(c2f.results, "c2f_results.rds")

    writeLines(c(
        '"BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS":',
        paste0('    flowViz: ', as.character(packageVersion('flowViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_dimensional_scatter_plots.csv versions.yml
    """
}

workflow BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GvHD ] ]

    main:
    BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS(ch_input)

    emit:
    tables   = BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS.out.tables
    plots    = BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS.out.plots
    objects  = BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS.out.objects
    versions = BIOC_FLOWVIZ_TWO_DIMENSIONAL_SCATTER_PLOTS.out.versions
}
