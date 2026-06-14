#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HERON — standard_epitope_protein_binding_analysis
// Identify significant binding probes, find epitope segments, and calculate epitope- and protein-level significance calls from raw sequence-level peptide array da
// Input: seq_mat, colData, probe_meta
// Container: quay.io/biocontainers/bioconductor-heron:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HERON, S4Vectors, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create HERONSequenceDataSet object
//  * 2. [Core Analysis] Quantile normalize sequence-level data
//  * 3. [Core Analysis] Calculate probe-level p-values and convert to probe dataset
//  * 4. [Core Analysis] Make probe-level calls and get K-of-N statistics
//  * 5. [Core Analysis] Find epitope segments
//  * 6. [Core Analysis] Calculate epitope-level p-values and add sequence annotations
//  * 7. [Core Analysis] Make epitope-level calls
//  * 8. [Core Analysis] Calculate protein-level p-values
//  * 9. [Core Analysis] Make protein-level calls

nextflow.enable.dsl = 2

process BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("HERON", "S4Vectors", "SummarizedExperiment")
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
    suppressPackageStartupMessages      library(SummarizedExperiment)
({
      library(HERON)
      library(S4Vectors)
    })
    
    # Helper function to load inputs robustly from the working directory
    load_input <- function(base_name, is_matrix = FALSE) {
      # Check RDS
      if (file.exists(paste0(base_name, ".rds"))) {
        return(readRDS(paste0(base_name, ".rds")))
      }
      # Check CSV
      if (file.exists(paste0(base_name, ".csv"))) {
        if (is_matrix) {
          return(as.matrix(read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)))
        } else {
          df <- read.csv(paste0(base_name, ".csv"), check.names = FALSE)
          return(df)
        }
      }
      # Check TSV
      if (file.exists(paste0(base_name, ".tsv"))) {
        if (is_matrix) {
          return(as.matrix(read.delim(paste0(base_name, ".tsv"), row.names = 1, check.names = FALSE)))
        } else {
          df <- read.delim(paste0(base_name, ".tsv"), check.names = FALSE)
          return(df)
        }
      }
      stop(paste("Error: Required input file not found for:", base_name))
    }
    
    # 1. Load User Inputs
    message("Loading input files...")
    seq_mat <- load_input("seq_mat", is_matrix = TRUE)
    
    colData_input <- load_input("colData", is_matrix = FALSE)
    if (!is(colData_input, "DataFrame")) {
      colData_input <- DataFrame(colData_input)
    }
    if ("SampleName" %in% colnames(colData_input)) {
      rownames(colData_input) <- colData_input\$SampleName
    }
    
    probe_meta <- load_input("probe_meta", is_matrix = FALSE)
    if (is(probe_meta, "DataFrame")) {
      probe_meta <- as.data.frame(probe_meta)
    }
    
    # 2. Create HERONSequenceDataSet object
    message("Creating HERONSequenceDataSet...")
    sds <- HERONSequenceDataSet(seq_mat)
    colData(sds) <- colData_input
    metadata(sds)\$probe_meta <- probe_meta
    
    # 3. Quantile normalize sequence-level data
    message("Quantile normalizing...")
    seq_ds_qn <- quantileNormalize(sds)
    
    # 4. Calculate probe-level p-values and convert to probe dataset
    message("Calculating probe-level p-values...")
    seq_pval_res <- calcCombPValues(seq_ds_qn)
    probe_pval_res <- convertSequenceDSToProbeDS(seq_pval_res)
    
    # 5. Make probe-level calls and get K-of-N statistics
    message("Making probe calls...")
    probe_calls_res <- makeProbeCalls(probe_pval_res)
    probe_calls_k_of_n <- getKofN(probe_calls_res)
    
    # 6. Find epitope segments
    message("Finding epitope segments...")
    epi_segments_uniq_res <- findEpitopeSegments(
        probe_calls_res,
        segment_method = "unique"
    )
    
    # 7. Calculate epitope-level p-values and add sequence annotations
    message("Calculating epitope p-values...")
    epi_padj_uniq <- calcEpitopePValues(
        probe_calls_res,
        epitope_ids = epi_segments_uniq_res,
        metap_method = "wmax1"
    )
    epi_padj_uniq <- addSequenceAnnotations(epi_padj_uniq)
    
    # 8. Make epitope-level calls
    message("Making epitope calls...")
    epi_calls_uniq <- makeEpitopeCalls(epi_padj_uniq, one_hit_filter = TRUE)
    
    # 9. Calculate protein-level p-values
    message("Calculating protein p-values...")
    prot_padj_uniq <- calcProteinPValues(
        epi_padj_uniq,
        metap_method = "tippetts"
    )
    
    # 10. Make protein-level calls
    message("Making protein calls...")
    prot_calls_uniq <- makeProteinCalls(prot_padj_uniq)
    
    # 11. Save Outputs
    message("Saving outputs...")
    write.csv(as.data.frame(assay(probe_calls_res, "calls")), "probe_calls.csv", row.names = TRUE)
    write.csv(probe_calls_k_of_n, "probe_calls_k_of_n.csv", row.names = TRUE)
    saveRDS(probe_calls_res, "probe_calls_res.rds")
    
    saveRDS(epi_segments_uniq_res, "epi_segments_uniq_res.rds")
    write.csv(as.data.frame(epi_segments_uniq_res), "epi_segments_uniq.csv", row.names = FALSE)
    
    epi_calls_k_of_n <- getKofN(epi_calls_uniq)
    write.csv(as.data.frame(assay(epi_calls_uniq, "calls")), "epi_calls.csv", row.names = TRUE)
    write.csv(epi_calls_k_of_n, "epi_calls_k_of_n.csv", row.names = TRUE)
    saveRDS(epi_calls_uniq, "epi_calls_uniq.rds")
    
    prot_calls_k_of_n <- getKofN(prot_calls_uniq)
    write.csv(as.data.frame(assay(prot_calls_uniq, "calls")), "prot_calls.csv", row.names = TRUE)
    write.csv(prot_calls_k_of_n, "prot_calls_k_of_n.csv", row.names = TRUE)
    saveRDS(prot_calls_uniq, "prot_calls_uniq.rds")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS":',
        paste0('    HERON: ', as.character(packageVersion('HERON')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_epitope_protein_binding_analysis.csv versions.yml
    """
}

workflow BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seq_mat, colData, probe_meta ] ]

    main:
    BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS.out.tables
    plots    = BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS.out.plots
    objects  = BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS.out.objects
    versions = BIOC_HERON_STANDARD_EPITOPE_PROTEIN_BINDING_ANALYSIS.out.versions
}
