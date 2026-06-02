#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MinimumDistance
// Analysis of de novo copy number variants in trios from high-dimensional genotyping platforms.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MinimumDistance/inst/doc/MinimumDistance.R
// Upstream  : SummarizedExperiment, VanillaICE, grid, oligoClasses
// Downstream: none
//
// Install: BiocManager::install("MinimumDistance")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MINIMUMDISTANCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-minimumdistance"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-minimumdistance:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-minimumdistance:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_minimumdistance_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_minimumdistance_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_minimumdistance_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MinimumDistance)
    library(ArrayViews)
    library(CopyNumScanParams)
    library(DNAcopyParam)
    library(FilterParamMD)
    library(GRanges)
    library(HmmTrellisParam)
    library(IRanges)
    library(MAP2)
    library(MinDistExperiment)
    library(MinDistParam)
    library(jsonlite)

    # --- Parsing Source Files [] ---
    # Key functions: parseSourceFile, parsedPath
    parsed_path <- parsedPath(views)
    invisible(sapply(
        views,
        parseSourceFile,
        param = scan_params
    ))
    parsed_files <- list.files(parsed_path)


    # --- Pedigree Construction and Experiment Setup [] ---
    # Key functions: ParentOffspring, ParentOffspringList, MinDistExperiment
    ped_list <- ParentOffspringList(pedigrees = list(
        ParentOffspring(
            id = "hapmap",
            father = "12287_03",
            mother = "12287_02",
            offspring = "12287_01",
            parsedPath = parsedPath(views)
        )
    ))
    me <- MinDistExperiment(views, pedigree = ped_list[[1]])


    # --- Minimum Distance Segmentation [] ---
    # Key functions: DNAcopyParam, MinDistParam, segment2, MAP2
    segment_params <- DNAcopyParam(alpha = 0.01)
    params <- MinDistParam(dnacopy = segment_params)
    mdgr <- segment2(me, params)
    md_g <- MAP2(me, mdgr, params)


    # --- CNV Filtering and De Novo Detection [] ---
    # Key functions: FilterParamMD, cnvFilter, denovoHemizygous, denovoHomozygous
    filter_param <- FilterParamMD(state = c("220", "221", "223"))
    cnvs <- cnvFilter(md_g, filter_param)
    denovo_hemi <- denovoHemizygous(md_g)
    denovo_homo <- denovoHomozygous(md_g)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_minimumdistance_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_minimumdistance_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_minimumdistance_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MINIMUMDISTANCE:", paste0("    minimumdistance: ", packageVersion("MinimumDistance"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_minimumdistance_results.csv
    touch ${prefix}_minimumdistance_output.rds
    echo "BIOC_MINIMUMDISTANCE:" > versions.yml
    echo "    minimumdistance: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MINIMUMDISTANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MINIMUMDISTANCE(ch_input)

    emit:
    results  = BIOC_MINIMUMDISTANCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MINIMUMDISTANCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MINIMUMDISTANCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MINIMUMDISTANCE.out.versions  // channel: path(versions.yml)
}
