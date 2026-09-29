#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — msea_enrichment_analysis
// MetaboAnalyst MSEA (Metabolite Set Enrichment Analysis). Two supported modes:
//   * ORA  (over-representation) — input = a list of compound names (compound_list.txt)
//   * QEA  (quantitative)        — input = a concentration table + a 2-group Label
// Standardises compound names (CrossReferencing), selects a metabolite-set library
// (SMPDB pathway-associated sets by default) and scores enrichment (hypergeometric for
// ORA, globaltest for QEA). Falls back to a built-in HMDB-mappable compound-list fixture
// (ORA) when no input is supplied.
// Input: compound_list.txt (ORA) OR concentration_table.csv + class_labels.csv (QEA).
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: ORA/QEA enrichment summary bar/dot plot
// NOTE: MSEA downloads its metabolite-set library (.qs) + the compound-name DB from
//       https://www.metaboanalyst.ca at runtime (cached to the work dir). The AWS Batch
//       compute subnets route 0.0.0.0/0 via an internet gateway, so this egress works.
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input] Detect mode: compound list -> ORA; concentration table -> QEA; else fixture (ORA)
//  * 2. [Name Mapping] CrossReferencing + CreateMappingResultTable (standardise compound names)
//  * 3. [ORA] Init msetora, SetCurrentMsetLib(smpdb_pathway), CalculateHyperScore -> msea_ora_result.csv
//  * 3'.[QEA] Init msetqea, normalize, SetCurrentMsetLib, CalculateGlobalTestScore -> msea_qea_result.csv
//  * 4. [Visualization & Output] Enrichment summary plot + result CSV + mSet RDS + name_map.csv

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS {
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
    def prefix = task.ext.prefix ?: "${meta.id}"
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

        # Ensure the Batch task exits promptly (kill the Rserve daemon MetaboAnalystR forks).
        .bm_finish <- function(status) {
          try(suppressWarnings(system("pkill -9 -f Rserve 2>/dev/null")), silent = TRUE)
          quit(save = "no", status = status, runLast = FALSE)
        }
        options(error = function() .bm_finish(1))

        find_input <- function(cands) { for (f in cands) if (file.exists(f)) return(f); NULL }
        cmpd_file <- find_input(c("compound_list.txt","compounds.txt","compound_list.csv"))
        conc_file <- find_input(c("concentration_table.csv","conc_table.csv","peak_intensity_table.csv","data.csv"))
        class_file <- find_input(c("class_labels.csv","sampleMetadata.csv","metadata.csv","labels.csv"))

        # Metabolite-set library: SMPDB pathway-associated sets (excludeNum=2 drops tiny sets).
        mset_lib <- "smpdb_pathway"

        if (is.null(conc_file)) {
          # ---------------- ORA (over-representation) mode ----------------
          if (!is.null(cmpd_file)) {
            cmpds <- readLines(cmpd_file); cmpds <- cmpds[nzchar(trimws(cmpds))]
          } else {
            # Self-contained fixture: 25 HMDB-primary compound names mappable by CrossReferencing("name").
            cmpds <- c("Acetoacetic acid","Beta-Alanine","Creatine","Dimethylglycine","Fumaric acid",
                       "Glycine","Homocysteine","L-Cysteine","L-Lysine","L-Serine","Pyruvic acid",
                       "Citric acid","L-Glutamine","L-Alanine","Succinic acid","L-Proline","L-Valine",
                       "Taurine","L-Tryptophan","Uric acid","L-Methionine","Malic acid",
                       "Oxoglutaric acid","L-Aspartic acid","L-Phenylalanine")
            message("No input supplied — using a built-in HMDB-mappable compound-list fixture (ORA).")
          }
          mSet <- InitDataObjects("conc", "msetora", FALSE)
          mSet <- Setup.MapData(mSet, cmpds)
          mSet <- CrossReferencing(mSet, "name")
          mSet <- CreateMappingResultTable(mSet)
          mSet <- SetMetabolomeFilter(mSet, FALSE)
          mSet <- SetCurrentMsetLib(mSet, mset_lib, 2)
          mSet <- CalculateHyperScore(mSet)     # MSEA ORA scorer (hypergeometric) -> msea_ora_result.csv
          tryCatch({ mSet <- PlotORA(mSet, "msea_ora_summary_", "net", "png", 72, NA) },
                   error = function(e) message("ORA summary plot skipped: ", conditionMessage(e)))
          # ora.mat also persisted explicitly (belt-and-braces alongside the auto-written CSV)
          tryCatch({ if (!is.null(mSet\$analSet\$ora.mat)) write.csv(as.data.frame(mSet\$analSet\$ora.mat), "msea_ora_enrichment.csv", row.names = TRUE) },
                   error = function(e) message("Could not persist ora.mat: ", conditionMessage(e)))
        } else {
          # ---------------- QEA (quantitative) mode ----------------
          # Normalise the input to the MetaboAnalyst "rowu" upload (samples in rows, col2 = Label).
          mat <- read.csv(conc_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
          if (!is.null(class_file)) {
            lab_df <- read.csv(class_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
            grp <- lab_df[[1]]; names(grp) <- rownames(lab_df)
            if (all(colnames(mat) %in% names(grp))) { samp <- colnames(mat); X <- t(mat) }
            else if (all(rownames(mat) %in% names(grp))) { samp <- rownames(mat); X <- as.matrix(mat) }
            else stop("Class labels could not be matched to the concentration table.")
            labels <- as.character(grp[samp])
          } else { samp <- colnames(mat); X <- t(mat); labels <- rep(c("GroupA","GroupB"), length.out = length(samp)) }
          ma_csv <- "metaboanalyst_qea_input.csv"
          out <- cbind(Sample = samp, Label = labels, as.data.frame(X, check.names = FALSE))
          write.csv(out, ma_csv, row.names = FALSE, quote = FALSE)

          mSet <- InitDataObjects("conc", "msetqea", FALSE)
          mSet <- Read.TextData(mSet, ma_csv, "rowu", "disc")
          mSet <- CrossReferencing(mSet, "name")
          mSet <- CreateMappingResultTable(mSet)
          mSet <- SanityCheckData(mSet)
          mSet <- ImputeMissingVar(mSet, method = "lod")
          mSet <- PreparePrenormData(mSet)
          mSet <- Normalization(mSet, "NULL", "LogNorm", "AutoNorm", ratio = FALSE, ratioNum = 20)
          mSet <- SetMetabolomeFilter(mSet, FALSE)
          mSet <- SetCurrentMsetLib(mSet, mset_lib, 2)
          mSet <- CalculateGlobalTestScore(mSet)   # QEA scorer (globaltest) -> msea_qea_result.csv
          tryCatch({ mSet <- PlotQEA.Overview(mSet, "msea_qea_summary_", "bar", "png", 72, NA) },
                   error = function(e) message("QEA overview plot skipped: ", conditionMessage(e)))
          tryCatch({ if (!is.null(mSet\$analSet\$qea.mat)) write.csv(as.data.frame(mSet\$analSet\$qea.mat), "msea_qea_enrichment.csv", row.names = TRUE) },
                   error = function(e) message("Could not persist qea.mat: ", conditionMessage(e)))
        }

        saveRDS(mSet, "metaboanalyst_msea_mSet.rds")
        cat("MetaboAnalystR MSEA enrichment pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msea_ora_result.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ compound_list.txt | concentration_table.csv (+ class_labels.csv) ] ]

    main:
    BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS.out.plots
    images   = BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS.out.images
    objects  = BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_METABOANALYSTR_MSEA_ENRICHMENT_ANALYSIS.out.versions
}
