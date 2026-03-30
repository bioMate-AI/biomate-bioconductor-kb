#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BaseSpaceR
// A rich R interface to Illumina's BaseSpace cloud computing environment, enabling the fast developmen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BaseSpaceR/inst/doc/BaseSpaceR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BaseSpaceR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASESPACER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basespacer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-basespacer:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-basespacer:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basespacer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basespacer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basespacer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AppAuth)
    library(AppResults)
    library(Genomes)
    library(Id)
    library(Name)
    library(Projects)
    library(Runs)
    library(TotalCount)
    library(Users)
    library(jsonlite)

    # --- Users [] ---
    # Key functions: Users
    u <- Users()
    u
    u$Id
    u$UserOwnedBy
    # --- Listgenomes [] ---
    # Key functions: listGenomes
    g <- listGenomes(aAuth, Limit = 100)
    g$SpeciesName
    # --- Listgenomes [] ---
    # Key functions: listGenomes, TotalCount
    listGenomes(aAuth, Limit = 2)
    g <- listGenomes(aAuth, Offset = 5, Limit = 2, SortBy = "Build")
    g
    TotalCount(g) # Collection size remains constant
    # --- Genomes [] ---
    # Key functions: Genomes
    Genomes(aAuth, id = 4)
    # --- Listruns [] ---
    # Key functions: listRuns
    r <- listRuns(aAuth)
    r
    # --- Runs [] ---
    # Key functions: Runs
    myRun <- Runs(r[1], simplify = TRUE)
    myRun
    # --- Listfiles [] ---
    # Key functions: listFiles, Name
    f <- listFiles(myRun)
    Name(f)
    # --- Listfiles [] ---
    # Key functions: listFiles
    listFiles(myRun, Limit = 2, Extensions = ".bcl")
    # --- Projects [] ---
    # Key functions: Projects, listProjects
    Projects(listProjects(aAuth, Limit = 1), simplify = TRUE)
    # --- Createproject [] ---
    # Key functions: createProject
    myNewProj <- createProject(aAuth, name = "My New Project")
    myNewProj
    # --- Listappresults [] ---
    # Key functions: listAppResults, AppResults
    reseq <- listAppResults(aAuth, projectId = 21383369, Limit = 1)
    AppResults(reseq)
    # --- Listfiles [] ---
    # Key functions: listFiles, AppResults, TotalCount, Name
    f <- listFiles(AppResults(reseq))
    TotalCount(f)
    Name(f)
    # --- Identical [] ---
    # Key functions: listFiles, Id
    identical(f, listFiles(aAuth, appResultId = Id(reseq)))
    # --- Listfiles [] ---
    # Key functions: listFiles, Id, Name
    f <- listFiles(aAuth, appResultId = Id(reseq), Extensions = ".bam")
    Name(f)
    # --- Listfiles [] ---
    # Key functions: listFiles, AppResults, Name, Id
    bamFiles <- listFiles(AppResults(reseq), Extensions = ".bam")
    Name(bamFiles)
    Id(bamFiles)
    bamFiles

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_basespacer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_basespacer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_basespacer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASESPACER:", paste0("    basespacer: ", packageVersion("BaseSpaceR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basespacer_results.csv
    touch ${prefix}_basespacer_output.rds
    echo "BIOC_BASESPACER:" > versions.yml
    echo "    basespacer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASESPACER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASESPACER(ch_input)

    emit:
    results  = BIOC_BASESPACER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASESPACER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASESPACER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASESPACER.out.versions  // channel: path(versions.yml)
}
