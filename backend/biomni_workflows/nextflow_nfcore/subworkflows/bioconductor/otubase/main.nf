#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OTUbase
// Provides a platform for Operational Taxonomic Unit based analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OTUbase/inst/doc/Introduction_to_OTUbase.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OTUbase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OTUBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-otubase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-otubase:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-otubase:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_otubase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_otubase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_otubase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OTUbase)
    library(jsonlite)

    # --- Dirpath [] ---
    # Key functions: file
    dirPath <- system.file("extdata/Sogin_2006", package="OTUbase")
    # --- Readotuset [] ---
    # Key functions: readOTUset
    soginOTU <- readOTUset(dirPath=dirPath, level="0.03", samplefile="sogin.groups", fastafile="sogin.fasta", otufile="sogin.unique.filter.fn.list", sampleADF="sample_metadata.txt")
    soginOTU
    # --- Readtaxset [] ---
    # Key functions: readTAXset
    soginTAX <- readTAXset(dirPath=dirPath, fastafile='sogin.fasta', sampleADF='sample_metadata.txt', taxfile='sogin.unique.fix.tax', namefile='sogin.names', samplefile='sogin.groups')
    soginTAX
    # --- Accessors [] ---
    # Key functions: id, sread, sampleID, sData
    head(id(soginOTU))
    head(sread(soginOTU))
    head(sampleID(soginOTU))
    head(sData(soginOTU))
    # --- Accessors [] ---
    # Key functions: otuID, tax
    head(otuID(soginOTU))
    head(tax(soginTAX))
    # --- Abundance [] ---
    # Key functions: abundance
    abundOTU <- abundance(soginOTU, weighted=F, collab='Site')
    head(abundOTU)
    abundTAX <- abundance(soginTAX, weighted=F, taxCol='genus', collab='Site')
    head(abundTAX)
    # --- Clustersamples [] ---
    # Key functions: clusterSamples
    clusterSamples(soginOTU, distmethod='jaccard', clustermethod='complete', collab='Site')
    clusterSamples(soginTAX, taxCol='genus', distmethod='jaccard', clustermethod='complete', collab='Site')
    # --- Subotuset [] ---
    # Key functions: subOTUset
    soginReduced <- subOTUset(soginOTU, samples=c("137", "138", "53R", "55R"))
    soginReduced

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_otubase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_otubase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_otubase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OTUBASE:", paste0("    otubase: ", packageVersion("OTUbase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_otubase_results.csv
    touch ${prefix}_otubase_output.rds
    echo "BIOC_OTUBASE:" > versions.yml
    echo "    otubase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OTUBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OTUBASE(ch_input)

    emit:
    results  = BIOC_OTUBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OTUBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OTUBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OTUBASE.out.versions  // channel: path(versions.yml)
}
