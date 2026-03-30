#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Oscope
// Oscope is a statistical pipeline developed to identifying and recovering the base cycle profiles of 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Oscope/inst/doc/Oscope_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Oscope")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OSCOPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-oscope"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-oscope:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-oscope:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_oscope_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_oscope_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_oscope_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CalcMV)
    library(FlagCluster)
    library(GetNormalizedMat)
    library(MedianNorm)
    library(NormForSine)
    library(OscopeENI)
    library(OscopeKM)
    library(OscopeSine)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, seed
    data(OscopeExampleData)
    str(OscopeExampleData)
    set.seed(10)
    # --- Mediannorm [] ---
    # Key functions: MedianNorm
    Sizes <- MedianNorm(OscopeExampleData)
    # --- Getnormalizedmat [] ---
    # Key functions: GetNormalizedMat
    DataNorm <- GetNormalizedMat(OscopeExampleData, Sizes)
    # --- Calcmv [] ---
    # Key functions: CalcMV
    MV <- CalcMV(Data = OscopeExampleData, Sizes = Sizes)
    str(MV$GeneToUse)
    DataSubset <- DataNorm[MV$GeneToUse,]
    # --- Normforsine [] ---
    # Key functions: NormForSine
    DataInput <- NormForSine(DataNorm)
    # --- Oscopesine [] ---
    # Key functions: OscopeSine
    ## SineRes <- OscopeSine(DataInput)
    ## str(SineRes)
    # --- Normforsine [] ---
    # Key functions: NormForSine, OscopeSine
    ## DataInput2 <- NormForSine(DataSubset)
    ## SineRes2 <- OscopeSine(DataInput2)
    # --- Oscopekm [] ---
    # Key functions: OscopeKM
    KMRes <- OscopeKM(SineRes, maxK = 10)
    print(KMRes)
    # --- Flagcluster [] ---
    # Key functions: FlagCluster
    ToRM <- FlagCluster(SineRes, KMRes, DataInput)
    # --- Oscopeeni [] ---
    # Key functions: OscopeENI
    ## ENIRes <- OscopeENI(KMRes = KMResUse, Data = DataInput, NCThre = 100)
    ## print(ENIRes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_oscope_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_oscope_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_oscope_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OSCOPE:", paste0("    oscope: ", packageVersion("Oscope"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oscope_results.csv
    touch ${prefix}_oscope_output.rds
    echo "BIOC_OSCOPE:" > versions.yml
    echo "    oscope: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OSCOPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OSCOPE(ch_input)

    emit:
    results  = BIOC_OSCOPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OSCOPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OSCOPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OSCOPE.out.versions  // channel: path(versions.yml)
}
