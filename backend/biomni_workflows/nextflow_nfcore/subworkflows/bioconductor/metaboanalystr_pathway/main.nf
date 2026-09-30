#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — metpa_pathway_analysis
// MetaboAnalyst MetPA pathway analysis: maps a compound-name list onto KEGG metabolic
// pathways for a chosen organism and scores pathway over-representation (Fisher exact)
// combined with topology impact (relative-betweenness-centrality node importance),
// yielding a ranked pathway table (p, FDR, Impact) + a pathway-summary scatter plot.
// Input: compound_list.txt
// Input-note: one compound name per line; organism KEGG code via params.kegg_org (default hsa).
//   Falls back to a built-in HMDB-mappable compound-list fixture (human, hsa) with no input.
//   The `// Input:` line must stay a bare comma-separated filename list (executor parses it as
//   the declared-input contract; prose there mis-tokenises into bogus params — fixed 2026-09-30).
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: pathway-analysis summary scatter (impact vs -log10 p)
// NOTE: In a container (non-web mode) MetPA's KEGG scoring path (CalculateOraScore) calls
//       the MetaboAnalyst web API at metaboanalyst.ca, and the compound-name DB / KEGG
//       pathway lib download from the same host. The AWS Batch compute subnets route
//       0.0.0.0/0 via an internet gateway, so this outbound HTTPS works. Organism is
//       parameterised via params.kegg_org (default 'hsa').
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input] Read compound-name list (or built-in fixture) + resolve organism KEGG code
//  * 2. [Name Mapping] Setup.MapData + CrossReferencing("name") + CreateMappingResultTable
//  * 3. [Pathway Library] SetKEGG.PathLib(org, current) + SetMetabolomeFilter(FALSE)
//  * 4. [Scoring] CalculateOraScore(nodeImp="rbc", method="fisher") -> pathway_results.csv
//  * 5. [Visualization & Output] PlotPathSummary scatter + pathway CSV + name_map.csv + mSet RDS

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.png"), emit: images, optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def kegg_org = params.kegg_org ?: 'hsa'
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment.
    .bm_deps <- c("MetaboAnalystR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      if (!requireNamespace("remotes", quietly=TRUE)) install.packages("remotes", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      .ma_deps <- c("impute","pcaMethods","siggenes","globaltest","GlobalAncova","Rgraphviz",
                    "KEGGgraph","SSPA","sva","limma","crmn","pls","caret","e1071","igraph",
                    "fitdistrplus","ellipse","scatterplot3d","pheatmap","RColorBrewer")
      .ma_miss <- .ma_deps[!vapply(.ma_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
      if (length(.ma_miss)) suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.ma_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.ma_miss), silent=TRUE))))
      if (!requireNamespace("MetaboAnalystR", quietly=TRUE)) suppressWarnings(suppressMessages(try(remotes::install_github("xia-lab/MetaboAnalystR", upgrade="never", quiet=TRUE, build=FALSE), silent=TRUE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }

        suppressPackageStartupMessages({ library(MetaboAnalystR) })

        .bm_finish <- function(status) {
          try(suppressWarnings(system("pkill -9 -f Rserve 2>/dev/null")), silent = TRUE)
          quit(save = "no", status = status, runLast = FALSE)
        }
        options(error = function() .bm_finish(1))

        kegg_org <- "${kegg_org}"

        find_input <- function(cands) { for (f in cands) if (file.exists(f)) return(f); NULL }
        cmpd_file <- find_input(c("compound_list.txt","compounds.txt","compound_list.csv"))
        if (!is.null(cmpd_file)) {
          cmpds <- readLines(cmpd_file); cmpds <- cmpds[nzchar(trimws(cmpds))]
        } else {
          cmpds <- c("Acetoacetic acid","Beta-Alanine","Creatine","Dimethylglycine","Fumaric acid",
                     "Glycine","Homocysteine","L-Cysteine","L-Lysine","L-Serine","Pyruvic acid",
                     "Citric acid","L-Glutamine","L-Alanine","Succinic acid","L-Proline","L-Valine",
                     "Taurine","L-Tryptophan","Uric acid","L-Methionine","Malic acid",
                     "Oxoglutaric acid","L-Aspartic acid","L-Phenylalanine")
          message("No input supplied — using a built-in HMDB-mappable compound-list fixture (org=", kegg_org, ").")
        }

        # ------------------------------------------------------------------
        # MetPA pathway ORA pipeline
        # ------------------------------------------------------------------
        mSet <- InitDataObjects("conc", "pathora", FALSE)
        mSet <- Setup.MapData(mSet, cmpds)
        mSet <- CrossReferencing(mSet, "name")
        mSet <- CreateMappingResultTable(mSet)
        mSet <- SetKEGG.PathLib(mSet, kegg_org, "current")
        mSet <- SetMetabolomeFilter(mSet, FALSE)
        # nodeImp="rbc" (relative betweenness centrality), method="fisher" — all positional, no defaults.
        mSet <- CalculateOraScore(mSet, "rbc", "fisher")   # -> pathway_results.csv (auto-written)

        tryCatch({ mSet <- PlotPathSummary(mSet, FALSE, "metpa_pathway_summary_", "png", 72, NA) },
                 error = function(e) message("Pathway summary plot skipped: ", conditionMessage(e)))

        # ora.mat = the pathway result matrix (Total/Expected/Hits/Raw p/-log10(p)/Holm/FDR/Impact)
        tryCatch({ if (!is.null(mSet\$analSet\$ora.mat)) write.csv(as.data.frame(mSet\$analSet\$ora.mat), "metpa_pathway_enrichment.csv", row.names = TRUE) },
                 error = function(e) message("Could not persist pathway ora.mat: ", conditionMessage(e)))

        saveRDS(mSet, "metaboanalyst_metpa_mSet.rds")
        cat("MetaboAnalystR MetPA pathway pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_results.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ compound_list.txt ] ]

    main:
    BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS.out.tables
    plots    = BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS.out.plots
    images   = BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS.out.images
    objects  = BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS.out.objects
    versions = BIOC_METABOANALYSTR_METPA_PATHWAY_ANALYSIS.out.versions
}
