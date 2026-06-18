#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOfuncR — custom_annotations_and_coordinates
// Run enrichment analysis using custom annotations, custom gene coordinates, or a custom GO-graph.
// Input: candidate_genes.tsv, custom_annotations.tsv, custom_coordinates.tsv
// Container: quay.io/biocontainers/bioconductor-gofuncr:1.30.0--r45ha27e39d_0
// R packages: GOfuncR
// Bioconductor: 3.20 | R: 4.4
// Requires: GOfuncR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define candidate genes
//  * 2. [Input & Preparation] Define custom annotations, coordinates, or GO-graph directory
//  * 3. [Core Analysis] Run go_enrich with custom parameters (annotations, gene_coords, or godir)

nextflow.enable.dsl = 2

process BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GOfuncR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(GOfuncR)
    
    # ==========================================
    # 1. Read User Inputs
    # ==========================================
    
    # Read candidate genes dataframe
    # Expected columns: gene_ids (character), is_candidate (numeric: 0 or 1)
    input_hyper = read.delim("candidate_genes.tsv", stringsAsFactors = FALSE)
    
    # Read custom annotations dataframe
    # Expected columns: gene (character), go_id (character)
    custom_anno = read.delim("custom_annotations.tsv", stringsAsFactors = FALSE)
    
    # Read custom coordinates dataframe
    # Expected columns: gene (character), chr (character), start (numeric), end (numeric)
    custom_coords = read.delim("custom_coordinates.tsv", stringsAsFactors = FALSE)
    
    
    # ==========================================
    # 2. Run Enrichment Analyses (Documented Code)
    # ==========================================
    
    # Run enrichment analysis with custom annotations
    res_hyper_anno = go_enrich(input_hyper, annotations=custom_anno)
    
    # Run enrichment analysis with custom coordinates and gene length correction
    res_hyper_cc = go_enrich(input_hyper, gene_len=TRUE, gene_coords=custom_coords)
    
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save results from custom annotations run
    saveRDS(res_hyper_anno, "res_hyper_anno.rds")
    write.csv(res_hyper_anno[[1]], "enrichment_results_custom_anno.csv", row.names = FALSE)
    
    # Save results from custom coordinates run
    saveRDS(res_hyper_cc, "res_hyper_cc.rds")
    write.csv(res_hyper_cc[[1]], "enrichment_results_custom_coords.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES":',
        paste0('    GOfuncR: ', as.character(packageVersion('GOfuncR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_annotations_and_coordinates.csv versions.yml
    """
}

workflow BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ candidate_genes.tsv, custom_annotations.tsv, custom_coordinates.tsv ] ]

    main:
    BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES(ch_input)

    emit:
    tables   = BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES.out.tables
    plots    = BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES.out.plots
    objects  = BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES.out.objects
    versions = BIOC_GOFUNCR_CUSTOM_ANNOTATIONS_AND_COORDINATES.out.versions
}
