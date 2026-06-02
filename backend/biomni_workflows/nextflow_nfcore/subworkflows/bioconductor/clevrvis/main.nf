#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clevRvis
// clevRvis provides a set of visualization techniques for clonal evolution. These include shark plots,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clevRvis/inst/doc/clevRvis.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("clevRvis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLEVRVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clevrvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clevrvis:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clevrvis:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clevrvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clevrvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clevrvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clevRvis)
    library(jsonlite)


    # --- Inputs [] ---
    # Key functions: createSeaObject
    ##Example data
    timepoints <- c(0,50,100)
    parents <- c(0,1,1,3,0,5,6)
    fracTable <- matrix(c(20,10,0,0,0,0,0,
                        40,20,15,0,30,10,0,
                        50,25,15,10,40,20,15),
                        ncol = length(timepoints))
    seaObject <- createSeaObject(fracTable, parents, timepoints,
                                timepointInterpolation = FALSE)
    ##seaObject with enabled time point estimation
    seaObject_tp <- createSeaObject(fracTable, parents, timepoints,
                                    timepointInterpolation = TRUE)
    ##seaObject with enabled time point estimation and therapy effect 
    ##estimation between time point 50 and 100
    seaObject_te <- createSeaObject(fracTable, parents, timepoints,
                                timepointInterpolation = TRUE,
                                therapyEffect = c(50,100))

    # --- Individual Colors [] ---
    # Key functions: createSeaObject, rainbow, sharkPlot
    ##seaObject with manually defined colors
    seaObject_col <- createSeaObject(fracTable, parents, timepoints,
                                    timepointInterpolation = TRUE,
                                    col = rainbow(7))
    #Basic shark plot showing legend and title
    sharkPlot(seaObject_tp, showLegend = TRUE, main = 'Example Shark plot')
    #Basic shark plot showing legend and title with manually defined color coding
    sharkPlot(seaObject_col, showLegend = TRUE, main = 'Example Shark plot')

    # --- Ext Shark [] ---
    # Key functions: extSharkPlot, dolphinPlot, timepoints, fractions
    ##extended shark plot, showing CCF as point size only for measured 
    ###time points, legend and title
    extSharkPlot(seaObject_tp, timepoints = timepoints, showLegend = TRUE, 
                main = 'Example Extended Shark plot')
    ##Dolphin plot, with vertical lines showing all time points, custom y axis 
    ##label and triangles indicating the measured time points
    dolphinPlot(seaObject_tp, showLegend = TRUE, 
                vlines = timepoints(seaObject), 
                vlab = timepoints(seaObject), vlabSize = 2, 
                ylab = 'Cancer cell fractions (CCFs)',
                markMeasuredTimepoints = timepoints)
    ##Dolphin plot polygon shape
    dolphinPlot(seaObject_tp, showLegend = TRUE, vlines = timepoints,
                vlab = timepoints, vlabSize = 2, 
                ylab = 'Cancer cell fractions (CCFs)', shape = 'polygon')

    # --- Bottom Dolph [] ---
    # Key functions: dolphinPlot, fractions, slot, timepoints
    ##Dolphin plot bottom layout and separated independent clones
    dolphinPlot(seaObject_tp, showLegend = FALSE,  vlines = timepoints,
                vlab = timepoints, vlabSize = 2, 
                ylab = 'Cancer cell fractions (CCFs)', 
                separateIndependentClones = TRUE, pos = 'bottom')
    ##Dolphin plot with annotations
    annotsTable <- data.frame(x = c(50,75), y = c(15,50), 
                                col = c('black', 'white'), 
                                lab = c('Annotation clone 5', 'Annotation clone 2'))
    dolphinPlot(seaObject_tp, showLegend = TRUE, main = 'Example Dolphin Plot', 
                vlines = timepoints, vlab = timepoints, vlabSize = 2, 
                ylab = 'Cancer cell fraction', annotations = annotsTable, 
                pos = 'bottom', separateIndependentClones = TRUE)
    ##Dolphin plot with enabled therapy effect estimation
    ##vertical lines show all time points, customized y axis label,
    ##triangles indicate the measured time points
    # --- Shark Dolph [] ---
    # Key functions: combinedPlot, plaicePlot
    ##Basic shark plot linked to dolphin plot
    combinedPlot(seaObject_tp, showLegend = TRUE, vlines = timepoints,
                vlab = timepoints, vlabSize = 2, ylab = 'Cancer cell fraction',
                separateIndependentClones = TRUE)
    #Plaice plot when all genes have at least one healthy copy
    plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                separateIndependentClones = TRUE)
    #Plaice plot showing biallelic events + annotations
    annotsTable <- data.frame(x = c(24,55), y = c(-40,-5), 
                                col = c('black', 'white'), 
                                lab = c('TP53', 'UBA1'))
    plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                separateIndependentClones = TRUE, clonesToFill = c(0,0,1,0,0,6,0),
                annotations = annotsTable)

    # --- Plaice Thp Eff [] ---
    # Key functions: plaicePlot, exploreTrees
    ##Plaice plot with enabled therapy effect estimation, 
    ##all genes are assumed to have at least one healthy copy
    plaicePlot(seaObject_te, showLegend = TRUE,  vlines = timepoints,
                vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                separateIndependentClones = TRUE)
    ##Alternative, valid parental relations are determined
    timepoints <- c(0,30,75,150)
    fracTable <- matrix(
                c( 100, 45, 00, 00,
                    20, 00, 00, 00,
                    30, 00, 20, 05,
                    98, 00, 55, 40),
                ncol=length(timepoints))

    trees <- exploreTrees(fracTable, timepoints)
    library(knitr)
    kable(data.frame(Clone=c("clone A","clone B","clone C","clone D"),
                    Parent=c("normal cell","clone A","clone B","clone C")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clevrvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clevrvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clevrvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLEVRVIS:", paste0("    clevrvis: ", packageVersion("clevRvis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clevrvis_results.csv
    touch ${prefix}_clevrvis_output.rds
    echo "BIOC_CLEVRVIS:" > versions.yml
    echo "    clevrvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLEVRVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLEVRVIS(ch_input)

    emit:
    results  = BIOC_CLEVRVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLEVRVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLEVRVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLEVRVIS.out.versions  // channel: path(versions.yml)
}
