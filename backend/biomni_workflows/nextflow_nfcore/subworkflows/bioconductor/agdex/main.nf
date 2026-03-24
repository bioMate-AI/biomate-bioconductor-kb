#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AGDEX
// A tool to evaluate agreement of differential expression for cross-species genomics
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AGDEX/inst/doc/AGDEX.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("AGDEX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AGDEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-agdex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-agdex:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-agdex:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_agdex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_agdex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_agdex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AGDEX)
    library(jsonlite)

    # --- Load Agdex Package And Data [] ---
    # Key functions: exprs, pData, all
    library(AGDEX)
    data(human.data)              # Load the human.data ExpressionSet object
    head(exprs(human.data)[,1:5]) # Preview the human expression data
    head(pData(human.data))       # Preview the human phenotype data
    table(pData(human.data)$grp)  # See number in each group
    # --- Prepare Dex.Set Object [] ---
    # Key functions: object
    # Create dex.set for human.comparison
    dex.set.human <- make.dex.set.object(Eset.data= human.data,
                                         comp.var=2,
                                         comp.def="human.tumor.typeD-other.human.tumors",
                                         gset.collection=gset.data)
    # --- Illustrate Structure Of Map.Data Object [] ---
    # Key functions: data
    data(map.data)
    names(map.data)
    head(map.data$probe.map)
    map.data$map.Aprobe.col
    map.data$map.Bprobe.col
    # --- Agdex Analysis [] ---
    # Key functions: agdex
    agdex.res<-agdex(dex.setA=dex.set.human,
                     dex.setB=dex.set.mouse,
                     map.data=map.data,
                     min.nperms=5,
                     max.nperms=10)
    # --- Agdex.Rnw:203 204 [] ---
    # Key functions: scatterplot
    agdex.scatterplot(agdex.res, gset.id=NULL)
    # --- Get Result Of Gene Sets Details [] ---
    # Key functions: details
    gset.res.stats<-get.gset.result.details(agdex.res, gset.ids = NULL, alpha=0.01)
    names(gset.res.stats)
    head(gset.res.stats$enrichA.details)
    head(gset.res.stats$agdex.details)
    dna.cat.process.gset.res<-get.gset.result.details(agdex.res, gset.ids="DNA_CATABOLIC_PROCESS")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_agdex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_agdex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_agdex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AGDEX:", paste0("    agdex: ", packageVersion("AGDEX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agdex_results.csv
    touch ${prefix}_agdex_output.rds
    echo "BIOC_AGDEX:" > versions.yml
    echo "    agdex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AGDEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AGDEX(ch_input)

    emit:
    results  = BIOC_AGDEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AGDEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AGDEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AGDEX.out.versions  // channel: path(versions.yml)
}
