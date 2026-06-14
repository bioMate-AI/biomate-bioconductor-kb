#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpeCond — standard_specond_analysis
// Perform a complete condition-specific gene detection analysis in a single function call and generate HTML and text reports.
// Input: expression_matrix.txt, expression_set.RData
// Container: quay.io/biocontainers/bioconductor-specond:1.64.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, SpeCond
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the full SpeCond analysis to fit mixture models and detect outliers
//  * 2. [Visualization & Output] Generate a comprehensive HTML results page with barplots and heatmaps
//  * 3. [Visualization & Output] Generate individual HTML pages for each gene to visualize expression profiles and density curves
//  * 4. [Visualization & Output] Export specific gene profiles, unique profiles, and gene summaries to text files

nextflow.enable.dsl = 2

process BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("SpeCond", "Biobase")
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
        library(SpeCond)
        library(Biobase)
        
        # ----------------------------------------------------------------------
        # 1. Read User Input Files
        # ----------------------------------------------------------------------
        if (file.exists("expression_matrix.txt")) {
          Mexp <- tryCatch({
            as.matrix(read.table("expression_matrix.txt", header=TRUE, sep="\t", row.names=1, check.names=FALSE))
          }, error = function(e) {
            as.matrix(read.table("expression_matrix.txt", header=TRUE, row.names=1, check.names=FALSE))
          })
        } else if (file.exists("expression_set.RData")) {
          env <- new.env()
          load("expression_set.RData", envir = env)
          eset_name <- names(env)[sapply(names(env), function(x) inherits(env[[x]], "ExpressionSet"))][1]
          if (!is.na(eset_name)) {
            Mexp <- exprs(env[[eset_name]])
          } else {
            stop("No ExpressionSet object found in expression_set.RData")
          }
        } else {
          stop("Required input file 'expression_matrix.txt' or 'expression_set.RData' not found in the working directory.")
        }
        
        # Ensure Mexp is a numeric matrix
        Mexp <- as.matrix(Mexp)
        storage.mode(Mexp) <- "numeric"
        
        # ----------------------------------------------------------------------
        # 2. Run SpeCond Analysis
        # ----------------------------------------------------------------------
        generalResult=SpeCond(Mexp, param.detection=NULL, multitest.correction.method="BY", prefix.file="E", print.hist.pv=TRUE, fit1=NULL, fit2=NULL, specificOutlierStep1=NULL)
        specificResult=generalResult\$specificResult
        
        # Save the primary R objects
        saveRDS(generalResult, file="generalResult.rds")
        saveRDS(specificResult, file="specificResult.rds")
        
        # ----------------------------------------------------------------------
        # 3. Generate HTML Reports
        # ----------------------------------------------------------------------
        tryCatch({
          getFullHtmlSpeCondResult(SpeCondResult=generalResult, param.detection=specificResult\$param.detection, page.name="Example_SpeCond_results", page.title="Tissue specific results", sort.condition="all", heatmap.profile=TRUE, heatmap.expression=FALSE, heatmap.unique.profile=FALSE, expressionMatrix=Mexp)
        }, error = function(e) {
          warning("Could not generate full HTML report: ", e\$message)
        })
        
        tryCatch({
          gene_ids <- seq_len(min(20, nrow(Mexp)))
          genePageInfo=getGeneHtmlPage(Mexp, specificResult, name.index.html="index_example_SpeCond_Results.html", gene.html.ids=gene_ids)
        }, error = function(e) {
          warning("Could not generate gene HTML pages: ", e\$message)
        })
        
        # ----------------------------------------------------------------------
        # 4. Export Specific Gene Profiles and Summaries to Text Files
        # ----------------------------------------------------------------------
        tryCatch({
          if (!is.null(specificResult\$L.specific.result\$M.specific) && nrow(specificResult\$L.specific.result\$M.specific) > 0) {
            L.specific.result.profile=getProfile(specificResult\$L.specific.result\$M.specific)
            writeSpeCondResult(specificResult\$L.specific.result,file.name.profile="Example_specific_profile.txt", file.specific.gene="Example_list_specific_gene.txt", file.name.unique.profile="Example_specific_unique_profile.txt")
            writeUniqueProfileSpecificResult(L.specific.result=specificResult\$L.specific.result, file.name.unique.profile="Example_specific_unique_profile.txt", full.list.gene=FALSE)
          } else {
            message("No condition-specific genes detected. Skipping profile text exports.")
          }
        }, error = function(e) {
          warning("Could not write specific profile results: ", e\$message)
        })
        
        tryCatch({
          gene_names_subset <- rownames(Mexp)[seq_len(min(10, nrow(Mexp)))]
          writeGeneResult(specificResult\$L.specific.result, file.name.result.gene="Example_gene_gummary_result.txt", gene.names=gene_names_subset)
        }, error = function(e) {
          warning("Could not write gene summary results: ", e\$message)
        })

    writeLines(c(
        '"BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS":',
        paste0('    SpeCond: ', as.character(packageVersion('SpeCond')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_specond_analysis.csv versions.yml
    """
}

workflow BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.txt, expression_set.RData ] ]

    main:
    BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS.out.tables
    plots    = BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS.out.plots
    objects  = BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS.out.objects
    versions = BIOC_SPECOND_STANDARD_SPECOND_ANALYSIS.out.versions
}
