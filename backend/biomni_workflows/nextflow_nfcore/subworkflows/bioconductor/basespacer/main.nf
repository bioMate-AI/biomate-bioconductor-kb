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
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("AppAuth", "AppResults", "Genomes", "Id", "Name", "Projects", "Runs", "TotalCount", "Users", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
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
    u\$Id
    u\$UserOwnedBy
    # --- Listgenomes [] ---
    # Key functions: listGenomes
    g <- listGenomes(aAuth, Limit = 100)
    g\$SpeciesName
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
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_basespacer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_basespacer_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_basespacer_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASESPACER:", paste0("    basespacer: ", as.character(packageVersion("BaseSpaceR")))),
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
