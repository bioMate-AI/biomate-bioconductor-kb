#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cyanoFilter
// An approach to filter out and/or identify phytoplankton cells from all particles measured via flow c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cyanoFilter/inst/doc/cyanoFilter.R
// Upstream  : dplyr, magrittr, tidyr, purrr, flowCore
// Downstream: none
//
// Install: BiocManager::install("cyanoFilter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYANOFILTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cyanofilter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cyanofilter:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cyanofilter:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cyanofilter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cyanofilter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cyanofilter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cyanoFilter)
    library(jsonlite)


    # --- Data And Preprocessing [] ---
    # Key functions: select, extdata, cyanoFilter
    metadata <- system.file("extdata", "2019-03-25_Rstarted.csv", 
      package = "cyanoFilter", 
      mustWork = TRUE)
    metafile <- read.csv(metadata, skip = 7, stringsAsFactors = FALSE, 
      check.names = TRUE)
    #columns containing dilution, $\mu l$ and id information
    metafile <- metafile %>% 
    # --- Metafile1 [] ---
    # Key functions: mutate, str_extract, str_detect
    #extract the part of the Sample.ID that corresponds to BS4 or BS5
    metafile <- metafile %>% dplyr::mutate(Sample.ID2 = 
                                             stringr::str_extract(metafile$Sample.ID, "BS*[4-5]")
                                           )
    #clean up the Cells.muL column
    names(metafile)[which(stringr::str_detect(names(metafile), "Cells."))] <- "CellspML"

    # --- Metafile2 [] ---
    # Key functions: mutate, goodFcs
    metafile <- metafile %>% mutate(Status = cyanoFilter::goodFcs(metafile = metafile, 
                                                                  col_cpml = "CellspML", 
                                            mxd_cellpML = 1000, 
                                            mnd_cellpML = 50)
                                    )
    knitr::kable(metafile)

    # --- Metafile3 [] ---
    # Key functions: group_by, nest, unlist, map, function, retain, maxi
    broken <- metafile %>% group_by(Sample.ID2) %>% nest()
    metafile$Retained <- unlist(map(broken$data, function(.x) {
      retain(meta_files = .x, make_decision = "maxi",
      Status = "Status",
      CellspML = "CellspML")
     })
    )
    knitr::kable(metafile)

    # --- Reading [] ---
    # Key functions: read.FCS, extdata, B4_18_1.fcs, cyanoFilter
    flowfile_path <- system.file("extdata", "B4_18_1.fcs", package = "cyanoFilter",
      mustWork = TRUE)
    flowfile <- read.FCS(flowfile_path, alter.names = TRUE,
      transformation = FALSE, emptyValue = FALSE,
      dataset = 1)
    flowfile

    # --- Remove Na [] ---
    # Key functions: noNA, ggpairsDens
    flowfile_nona <- noNA(x = flowfile)
    ggpairsDens(flowfile_nona, notToPlot = "TIME")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cyanofilter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cyanofilter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cyanofilter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYANOFILTER:", paste0("    cyanofilter: ", packageVersion("cyanoFilter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cyanofilter_results.csv
    touch ${prefix}_cyanofilter_output.rds
    echo "BIOC_CYANOFILTER:" > versions.yml
    echo "    cyanofilter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYANOFILTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYANOFILTER(ch_input)

    emit:
    results  = BIOC_CYANOFILTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYANOFILTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYANOFILTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYANOFILTER.out.versions  // channel: path(versions.yml)
}
