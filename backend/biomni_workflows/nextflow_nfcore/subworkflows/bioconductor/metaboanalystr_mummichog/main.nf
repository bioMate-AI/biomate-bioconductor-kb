#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — mummichog_ms_peaks_to_pathways
// MetaboAnalyst "MS Peaks to Pathways" (mummichog algorithm). Takes an untargeted
// LC-MS peak list (m/z, p-value, t-score) with an instrument mass-accuracy + ionisation
// mode, tentatively annotates m/z to compounds and runs pathway-set enrichment analysis
// (PSEA) against a KEGG/BioCyc metabolic model, yielding a ranked pathway table
// (Fisher/EASE p, hits) + an enrichment scatter plot — no prior compound identification
// required.
// Input: peaklist.txt
// Input-note: tab/CSV with columns m.z, p.value, t.score; instrument ppm + ms mode via params.
//   Falls back to a self-contained synthetic peak-list fixture (positive mode, 5 ppm) with no
//   input. The `// Input:` line must stay a bare comma-separated filename list (executor parses
//   it as the declared-input contract; prose mis-tokenises into bogus params — fixed 2026-09-30).
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: peaks-to-pathways enrichment scatter (enrichment factor vs -log10 p)
// NOTE: PerformPSEA downloads the pathway model library (<lib>.qs, e.g. hsa_mfn.qs) from
//       https://www.metaboanalyst.ca/resources/libs/mummichog/ at runtime (cached to the
//       work dir). AWS Batch compute subnets route 0.0.0.0/0 via an internet gateway, so
//       this egress works. Params: ms_mode (positive/negative/mixed), instrument_ppm, lib.
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input] Read peak list (m.z/p.value/t.score) or synthesize a fixture; set instrument params
//  * 2. [Init] InitDataObjects(mass_all/mummichog) + SetPeakFormat + UpdateInstrumentParameters
//  * 3. [Load] Read.PeakListData + SanityCheckMummichogData + SetMummichogPval(0.05)
//  * 4. [PSEA] PerformPSEA(lib=hsa_mfn) -> mummichog_pathway_enrichment_mummichog.csv + matched compounds
//  * 5. [Visualization & Output] PlotPeaks2Paths scatter + result CSVs + mSet RDS

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS {
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
    def prefix     = task.ext.prefix ?: "${meta.id}"
    def ms_mode    = params.ms_mode ?: 'positive'
    def ppm        = params.instrument_ppm ?: 5
    def psea_lib   = params.mummichog_lib ?: 'hsa_mfn'
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

        ms_mode  <- "${ms_mode}"
        ppm      <- as.numeric("${ppm}")
        psea_lib <- "${psea_lib}"

        find_input <- function(cands) { for (f in cands) if (file.exists(f)) return(f); NULL }
        peak_file <- find_input(c("peaklist.txt","peak_list.txt","peaks.txt","peaklist.csv","peak_list.csv"))

        if (is.null(peak_file)) {
          # ---- Self-contained fixture: ~300 peaks, ~50 significant (p<0.05) so the
          #      SetMummichogPval guard (needs >=11 significant features) passes. ----
          set.seed(7)
          n_tot <- 300L; n_sig <- 50L
          mz <- round(runif(n_tot, 80, 600), 4)
          pval <- c(runif(n_sig, 1e-5, 0.049), runif(n_tot - n_sig, 0.06, 1.0))
          tsc  <- c(runif(n_sig, 2.1, 6.5) * sample(c(1,-1), n_sig, TRUE), runif(n_tot - n_sig, -2.0, 2.0))
          ord <- sample(n_tot)
          peaks <- data.frame(m.z = mz[ord], p.value = round(pval[ord], 6), t.score = round(tsc[ord], 4))
          peak_file <- "peaklist.txt"
          write.table(peaks, peak_file, sep = "\\t", row.names = FALSE, quote = FALSE)
          message("No input supplied — using a synthetic peak-list fixture (", n_tot, " peaks, ", n_sig, " significant).")
        }

        # ------------------------------------------------------------------
        # Mummichog / MS Peaks to Pathways pipeline
        # ------------------------------------------------------------------
        mSet <- InitDataObjects("mass_all", "mummichog", FALSE)
        mSet <- SetPeakFormat(mSet, "mpt")   # m.z + p.value + t.score
        mSet <- UpdateInstrumentParameters(mSet, ppm, ms_mode, "yes", 0.02, NA)
        mSet <- Read.PeakListData(mSet, peak_file)
        # SetPeakEnrichMethod initializes paramSet version (+ anal.type); without it PerformPSEA's
        # guard (if !mumRT and version equals v2) sees version=NULL -> "missing value where
        # TRUE/FALSE needed" inside .setup.psea.library (root-caused 2026-10-01 on a real Batch run).
        mSet <- SetPeakEnrichMethod(mSet, "mum", "v2")
        mSet <- SanityCheckMummichogData(mSet)
        mSet <- SetMummichogPval(mSet, 0.05)
        # PerformPSEA(lib, libVersion, minLib=3, permNum=100). Downloads <lib>.qs from metaboanalyst.ca.
        mSet <- PerformPSEA(mSet, psea_lib, "current", 3, 100)

        tryCatch({ mSet <- PlotPeaks2Paths(mSet, "mummichog_peaks_to_paths_", "png", 300, 9) },
                 error = function(e) message("Peaks-to-paths plot skipped: ", conditionMessage(e)))

        # mummichog ORA result matrix (auto-written to mummichog_pathway_enrichment_mummichog.csv);
        # persist the slot too as a stable filename.
        tryCatch({ if (!is.null(mSet\$mummi.resmat)) write.csv(as.data.frame(mSet\$mummi.resmat), "mummichog_pathway_enrichment.csv", row.names = TRUE) },
                 error = function(e) message("Could not persist mummi.resmat: ", conditionMessage(e)))

        saveRDS(mSet, "metaboanalyst_mummichog_mSet.rds")
        cat("MetaboAnalystR mummichog MS-peaks-to-pathways pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mummichog_pathway_enrichment.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaklist.txt ] ]

    main:
    BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS.out.tables
    plots    = BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS.out.plots
    images   = BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS.out.images
    objects  = BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS.out.objects
    versions = BIOC_METABOANALYSTR_MUMMICHOG_MS_PEAKS_TO_PATHWAYS.out.versions
}
