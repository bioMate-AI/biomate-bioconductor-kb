#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: annotationTools — cross_species_probeset_mapping
// Map all probe sets from a source microarray platform to their orthologous probe sets on a target platform to build a translation table.
// Input: HG-U133_Plus_2_annot.csv, Mouse430_2_annot.csv, homologene.data
// Container: quay.io/biocontainers/bioconductor-annotationtools:1.84.0--r45hdfd78af_0
// R packages: annotationTools
// Bioconductor: 3.20 | R: 4.4
// Requires: annotationTools
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load source and target annotation files and the
//  * 2. [Visualization & Output] Map source probe sets to Entrez Gene IDs
//  * 3. [Visualization & Output] Find target species orthologous Gene IDs using getHOMOLOG
//  * 4. [Visualization & Output] Map target Gene IDs to target probe sets using getPROBESET
//  * 5. [Visualization & Output] Compact and clean the mapped lists using compactList to
//  * 6. [Visualization & Output] Combine and write the final mapping table to a text file

nextflow.enable.dsl = 2

process BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("annotationTools")
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
    library(annotationTools)
    library(stats)
    
    # --- Load source and target annotation files and the ---
    annotation_HGU133Plus2 <- read.csv('HG-U133_Plus_2_annot.csv',
                                       colClasses = 'character', comment.char = '#')
    annotation_Mouse4302 <- read.csv('Mouse430_2_annot.csv',
                                     colClasses = 'character', comment.char = '#')
    homologene <- read.delim('homologene.data', header = FALSE)
    target_species <- 10090
    
    # --- Map source probe sets to Entrez Gene IDs ---
    ps_HGU133Plus2 <- annotation_HGU133Plus2[, 1]
    gid_HGU133Plus2 <- getGENEID(ps_HGU133Plus2, annotation_HGU133Plus2)
    length_gid_HGU133Plus2 <- sapply(gid_HGU133Plus2, function(x) { length(x) })
    
    # --- Find target species orthologous Gene IDs using getHOMOLOG ---
    gid_Mouse4302 <- getHOMOLOG(unlist(gid_HGU133Plus2), target_species, homologene)
    length_gid_Mouse4302 <- sapply(gid_Mouse4302, function(x) { length(x) })
    
    # --- Map target Gene IDs to target probe sets using getPROBESET ---
    ps_Mouse4302 <- getPROBESET(unlist(gid_Mouse4302), annotation_Mouse4302)
    
    # --- Compact and clean the mapped lists using compactList to ---
    ps_Mouse4302_1 <- compactList(ps_Mouse4302, length_gid_Mouse4302)
    ps_Mouse4302_2 <- compactList(ps_Mouse4302_1, length_gid_HGU133Plus2)
    gid_Mouse4302_1 <- compactList(gid_Mouse4302, length_gid_HGU133Plus2)
    
    ps_Mouse4302_2 <- lapply(ps_Mouse4302_2, function(x) { unique(x) })
    ps_Mouse4302_2 <- lapply(ps_Mouse4302_2, function(x) {
      if (length(x) > 1) na.omit(x) else x
    })
    gid_Mouse4302_1 <- lapply(gid_Mouse4302_1, function(x) { unique(x) })
    gid_Mouse4302_1 <- lapply(gid_Mouse4302_1, function(x) {
      if (length(x) > 1) na.omit(x) else x
    })
    
    # --- Combine and write the final mapping table to a text file ---
    orthoTable <- cbind(ps_HGU133Plus2, listToCharacterVector(gid_HGU133Plus2, sep = ','),
                        listToCharacterVector(gid_Mouse4302_1, sep = ','),
                        listToCharacterVector(ps_Mouse4302_2, sep = ','))
    colnames(orthoTable) <- c('ps_HGU133Plus2', 'gid_HGU133Plus2',
                              'gid_Mouse4302', 'ps_Mouse4302')
    write.table(orthoTable, file = 'HGU133Plus2_Mouse4302.txt', sep = '\t',
                col.names = TRUE, row.names = FALSE)
    
    # Perform the entire process using the wrapper function ps2ps and overwrite/save
    orthoTable <- ps2ps(annotation_HGU133Plus2, annotation_Mouse4302, homologene, 10090)
    write.table(orthoTable, file = 'HGU133Plus2_Mouse4302.txt', sep = '\t',
                col.names = TRUE, row.names = FALSE)
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING":',
        paste0('    annotationTools: ', as.character(packageVersion('annotationTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_species_probeset_mapping.csv versions.yml
    """
}

workflow BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HG-U133_Plus_2_annot.csv, Mouse430_2_annot.csv, homologene.data ] ]

    main:
    BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING(ch_input)

    emit:
    tables   = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING.out.tables
    plots    = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING.out.plots
    objects  = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING.out.objects
    versions = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_PROBESET_MAPPING.out.versions
}
