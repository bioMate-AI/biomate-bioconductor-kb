#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affy
// The package contains functions for exploratory oligonucleotide array analysis. The dependence on tkW
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affy/inst/doc/affy.R
// Upstream  : affydata
// Downstream: affyContam, affyPLM, AffyRNADegradation, altcdfenvs, arrayMvout
//
// Install: BiocManager::install("affy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affy:1.84.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affy:1.84.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AffyRNAdeg)
    library(MAplot)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: methods
    library(affydata)
    data(Dilution) ##data included in the package for examples
    normalize.methods(Dilution)
    # --- Methods [] ---
    # Key functions: methods
    express.summary.stat.methods()
    # --- Mas5 [] ---
    # Key functions: mas5
    eset <- mas5(Dilution)
    # --- mas5calls [] ---
    # Key functions: mas5calls
    Calls <- mas5calls(Dilution)
    # --- Rma [] ---
    # Key functions: rma
    eset <- rma(Dilution)
    # --- Phenodata [] ---
    # Key functions: phenoData, pData
    phenoData(Dilution)
    pData(Dilution)
    # --- Data [] ---
    # Key functions: MAplot
    data(Dilution)
    MAplot(Dilution,pairs=TRUE,plot.method="smoothScatter")
    # --- Samplenames [] ---
    # Key functions: sampleNames
    sampleNames(Dilution)
    # --- Mean [] ---
    # Key functions: mm, pm
    mean(mm(Dilution)>pm(Dilution))
    # --- Genenames [] ---
    # Key functions: geneNames, pm
    gn <- geneNames(Dilution)
    pm(Dilution, gn[100])
    # --- Affyrnadeg [] ---
    # Key functions: AffyRNAdeg
    deg <- AffyRNAdeg(Dilution)
    names(deg)
    # --- Summaryaffyrnadeg [] ---
    # Key functions: summaryAffyRNAdeg
    summaryAffyRNAdeg(deg)
    # --- Normalize [] ---
    # Key functions: normalize
    Dilution.normalized <- normalize(Dilution)
    # --- Featurenames [] ---
    # Key functions: featureNames, probeset, show
    gn <- featureNames(Dilution)
    ps <- probeset(Dilution, gn[1:2])
    #this is what i should be using: ps
    show(ps[[1]])
    # --- List [] ---
    # Key functions: cbind
    mylocation <- list("1000_at"=cbind(pm=c(1,2,3),mm=c(4,5,6)),
                       "1001_at"=cbind(pm=c(4,5,6),mm=c(1,2,3)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFY:", paste0("    affy: ", packageVersion("affy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affy_results.csv
    touch ${prefix}_affy_output.rds
    echo "BIOC_AFFY:" > versions.yml
    echo "    affy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFY(ch_input)

    emit:
    results  = BIOC_AFFY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFY.out.versions  // channel: path(versions.yml)
}
