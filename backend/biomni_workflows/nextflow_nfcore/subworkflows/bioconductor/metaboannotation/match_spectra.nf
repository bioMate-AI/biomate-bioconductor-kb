#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnnotation — match_spectra
// Match experimental MS2 spectra against a reference spectral library (such as MassBank or a custom Spectra object).
// Input: PestMix1_DDA.mzML, minimb.RData
// Container: quay.io/biocontainers/bioconductor-metaboannotation:1.14.0--r45hdfd78af_0
// R packages: MetaboAnnotation, Spectra, msentropy
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnnotation, Spectra, msentropy
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load query and target Spectra objects
//  * 2. [Input & Preparation] Define similarity parameters using CompareSpectraParam or MatchForwardReverseParam
//  * 3. [Core Analysis] Perform spectral matching using matchSpectra()
//  * 4. [Visualization & Output] Extract, filter, and visualize matches using spectraData() and plotSpectraMirror()

nextflow.enable.dsl = 2

process BIOC_METABOANNOTATION_MATCH_SPECTRA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("MetaboAnnotation", "Spectra", "msentropy")
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
        library(Spectra)
        library(MetaboAnnotation)
        library(msentropy)
        
        # 1. Load query and target Spectra objects from user input files
        # Read experimental MS2 spectra from the local mzML file
        fl <- "PestMix1_DDA.mzML"
        pest_ms2 <- filterMsLevel(Spectra(fl), 2L)
        pest_ms2\$feature_id <- paste0("FT", seq_along(pest_ms2))
        pest_ms2\$spectrum_id <- paste0("sp_", seq_along(pest_ms2))
        
        # Load reference spectra from the local RData file
        load("minimb.RData")
        
        # 2. Define similarity parameters and perform spectral matching (CompareSpectraParam)
        csp <- CompareSpectraParam(requirePrecursor = TRUE, ppm = 10, matchedPeaksCount = TRUE)
        mtches <- matchSpectra(pest_ms2, minimb, param = csp)
        
        # Inspect matching results
        length(pest_ms2)
        length(mtches)
        if (length(mtches) > 0) {
            mtches[1]
        }
        if (length(mtches) > 1) {
            mtches[2]
            mtches[2]\$target_compound_name
        }
        spectraVariables(mtches)
        mtches\$spectrum_id
        mtches\$.original_query_index
        query(mtches)\$.original_query_index
        
        # Extract and save matches
        mtches_df <- spectraData(mtches, columns = c("spectrum_id", "feature_id", "score", "target_spectrum_id", "target_compound_name"))
        write.csv(as.data.frame(mtches_df), "matches_compare_spectra.csv", row.names = FALSE)
        
        # 3. Visualize matches using plotSpectraMirror()
        pdf("spectra_mirror_plots.pdf", width = 8, height = 6)
        if (length(mtches) > 0) {
            plot_idx <- 1
            matched_queries <- whichQuery(mtches)
            if (length(matched_queries) > 0) {
                plot_idx <- matched_queries[1]
            }
            
            plotSpectraMirror(mtches[plot_idx])
            
            # Apply scaling function and plot again
            scale_int <- function(x, ...) {
                x[, "intensity"] <- x[, "intensity"] / max(x[, "intensity"], na.rm = TRUE)
                x
            }
            mtches <- addProcessing(mtches, scale_int)
            plotSpectraMirror(mtches[plot_idx])
        }
        dev.off()
        
        # Save the processed MatchedSpectra object
        saveRDS(mtches, "matched_spectra_processed.rds")
        
        # 4. Match using MatchForwardReverseParam
        mp <- MatchForwardReverseParam(requirePrecursor = TRUE, ppm = 10)
        mtches_fr <- matchSpectra(pest_ms2, minimb, param = mp)
        fr_df <- as.data.frame(spectraData(mtches_fr, c("spectrum_id", "target_spectrum_id", "target_compound_name", "score", "reverse_score", "presence_ratio")))
        write.csv(fr_df, "matches_forward_reverse.csv", row.names = FALSE)
        
        # 5. Match selecting only the top match (CompareSpectraParam with THRESHFUN)
        select_top_match <- function(x) {
            which.max(x)
        }
        csp2 <- CompareSpectraParam(ppm = 10, requirePrecursor = FALSE, THRESHFUN = select_top_match)
        mtches_top <- matchSpectra(pest_ms2, minimb, param = csp2)
        res_top <- spectraData(mtches_top, columns = c("spectrum_id", "target_spectrum_id", "target_compound_name", "score"))
        write.csv(as.data.frame(res_top), "matches_top_match.csv", row.names = FALSE)
        
        # 6. Match using alternative similarity function (msentropy)
        csp_entropy <- CompareSpectraParam(requirePrecursor = TRUE, ppm = 10, matchedPeaksCount = TRUE, MAPFUN = joinPeaksNone, FUN = msentropy_similarity, ms2_tolerance_in_ppm = 10, ms2_tolerance_in_da = -1)
        mtches_entropy <- matchSpectra(pest_ms2, minimb, param = csp_entropy)
        entropy_df <- spectraData(mtches_entropy, columns = c("spectrum_id", "feature_id", "score", "target_spectrum_id", "target_compound_name"))
        write.csv(as.data.frame(entropy_df), "matches_entropy.csv", row.names = FALSE)
        
        # 7. Match against MassBankSource (wrapped in tryCatch for robustness against network/AnnotationHub issues)
        tryCatch({
            mbank <- MassBankSource("2022.06")
            res_mbank <- matchSpectra(pest_ms2, mbank, param = CompareSpectraParam(requirePrecursor = TRUE, ppm = 10))
            target(res_mbank)
            mbank_df <- data.frame(
                spectrum_id = res_mbank\$spectrum_id,
                target_name = matchedData(res_mbank)\$target_name
            )
            write.csv(mbank_df, "matches_massbank_source.csv", row.names = FALSE)
        }, error = function(e) {
            message("Could not complete MassBankSource matching: ", e\$message)
        })

    writeLines(c(
        '"BIOC_METABOANNOTATION_MATCH_SPECTRA":',
        paste0('    MetaboAnnotation: ', as.character(packageVersion('MetaboAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_match_spectra.csv versions.yml
    """
}

workflow BIOC_METABOANNOTATION_MATCH_SPECTRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PestMix1_DDA.mzML, minimb.RData ] ]

    main:
    BIOC_METABOANNOTATION_MATCH_SPECTRA(ch_input)

    emit:
    tables   = BIOC_METABOANNOTATION_MATCH_SPECTRA.out.tables
    plots    = BIOC_METABOANNOTATION_MATCH_SPECTRA.out.plots
    objects  = BIOC_METABOANNOTATION_MATCH_SPECTRA.out.objects
    versions = BIOC_METABOANNOTATION_MATCH_SPECTRA.out.versions
}
