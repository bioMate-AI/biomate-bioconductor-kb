#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AlphaMissenseR — protein_structure_visualization
// Map and visualize AlphaMissense pathogenicity scores onto 3D protein structures predicted by AlphaFold.
// Input: uniprot_id
// Container: quay.io/biocontainers/bioconductor-alphamissenser:1.6.1--r45hdfd78af_0
// R packages: AlphaMissenseR, bio3d, dplyr, htmlwidgets, r3dmol, readr
// Bioconductor: 3.20 | R: 4.4
// Requires: AlphaMissenseR, BiocFileCache, bio3d, dplyr, htmlwidgets, r3dmol, readr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve AlphaMissense amino acid substitutions for the UniProt ID
//  * 2. [Core Analysis] Query AlphaFold API for the protein structure metadata using af_predictions()
//  * 3. [Input & Preparation] Download and read the PDB structure file using bio3d::read.pdb()
//  * 4. [Core Analysis] Calculate average pathogenicity per amino acid position using am_aa_pathogenicity()
//  * 5. [Core Analysis] Generate a position-based color function using af_colorfunc_by_position()
//  * 6. [Visualization & Output] Render the 3D structure colored by pathogenicity using r3dmol

nextflow.enable.dsl = 2

process BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION {
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
    .bm_deps <- c("AlphaMissenseR", "bio3d", "dplyr", "htmlwidgets", "r3dmol", "readr")
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
    
    # Load required libraries
    library(AlphaMissenseR)
    library(dplyr)
    library(bio3d)
    library(r3dmol)
    library(htmlwidgets)
    library(readr)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    if (!file.exists("uniprot_id")) {
      stop("Required input file 'uniprot_id' not found in the working directory.")
    }
    
    uniprot_id <- trimws(readLines("uniprot_id", warn = FALSE)[1])
    if (uniprot_id == "") {
      stop("The 'uniprot_id' file is empty. Please provide a valid UniProt accession ID.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Retrieve AlphaMissense amino acid substitutions for the UniProt ID
    # -----------------------------------------------------------------------------
    P35557_aa <- am_data("aa_substitutions") |> dplyr::filter(uniprot_id == !!uniprot_id)
    
    # Generate and save the prediction view widget
    p_view <- af_prediction_view(P35557_aa)
    htmlwidgets::saveWidget(p_view, "prediction_view.html", selfcontained = TRUE)
    
    # -----------------------------------------------------------------------------
    # 3. Query AlphaFold API for the protein structure metadata
    # -----------------------------------------------------------------------------
    # Construct a prefix pattern to find related UniProt IDs, mimicking the vignette's %like% query
    prefix <- paste0(substr(uniprot_id, 1, 5), "%")
    
    uniprot_ids <- am_data("aa_substitutions") |> 
      dplyr::filter(uniprot_id %like% !!prefix) |> 
      dplyr::distinct(uniprot_id) |> 
      dplyr::pull(uniprot_id)
    
    # Ensure the target uniprot_id is included in the query list
    if (!(uniprot_id %in% uniprot_ids)) {
      uniprot_ids <- c(uniprot_id, uniprot_ids)
    }
    
    prediction <- af_predictions(uniprot_ids)
    
    # Extract the PDB URL for the specific UniProt ID of interest
    pdb_url <- prediction |> 
      dplyr::filter(uniprotAccession == !!uniprot_id) |> 
      dplyr::pull(pdbUrl)
    
    if (length(pdb_url) == 0) {
      # Fallback: query specifically for the single target UniProt ID if the prefix search missed it
      prediction_fallback <- af_predictions(uniprot_id)
      pdb_url <- prediction_fallback |> 
        dplyr::filter(uniprotAccession == !!uniprot_id) |> 
        dplyr::pull(pdbUrl)
    }
    
    if (length(pdb_url) == 0) {
      stop(paste("Could not retrieve AlphaFold PDB URL for UniProt ID:", uniprot_id))
    }
    
    # -----------------------------------------------------------------------------
    # 4. Download and read the PDB structure file
    # -----------------------------------------------------------------------------
    pdb_file <- BiocFileCache::bfcrpath(rnames = basename(pdb_url), fpath = pdb_url)
    pdb <- bio3d::read.pdb(pdb_file)
    
    # -----------------------------------------------------------------------------
    # 5. Calculate average pathogenicity per amino acid position
    # -----------------------------------------------------------------------------
    P35557 <- am_data("hg38") |> dplyr::filter(uniprot_id == !!uniprot_id)
    pathogenicity <- am_aa_pathogenicity(P35557)
    
    # Save pathogenicity scores to a CSV file
    readr::write_csv(as.data.frame(pathogenicity), "pathogenicity_scores.csv")
    
    # -----------------------------------------------------------------------------
    # 6. Generate a position-based color function
    # -----------------------------------------------------------------------------
    colorfunc <- pathogenicity |> 
      af_colorfunc_by_position("aa_pos", "aa_pathogenicity_mean", length(pdb\$seqres))
    
    # -----------------------------------------------------------------------------
    # 7. Render the 3D structure colored by pathogenicity
    # -----------------------------------------------------------------------------
    r3d_plot <- r3dmol::r3dmol() |> 
      r3dmol::m_add_model(r3dmol::m_bio3d(pdb)) |> 
      r3dmol::m_set_style(style = r3dmol::m_style_cartoon(arrow = TRUE, colorfunc = colorfunc)) |> 
      r3dmol::m_zoom_to()
    
    # Save the interactive 3D visualization as an HTML file
    htmlwidgets::saveWidget(r3d_plot, "protein_3d_visualization.html", selfcontained = TRUE)
    
    # -----------------------------------------------------------------------------
    # Clean up database connections
    # -----------------------------------------------------------------------------
    db_disconnect_all()

    writeLines(c(
        '"BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION":',
        paste0('    AlphaMissenseR: ', as.character(packageVersion('AlphaMissenseR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_structure_visualization.csv versions.yml
    """
}

workflow BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ uniprot_id ] ]

    main:
    BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION.out.tables
    plots    = BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION.out.plots
    objects  = BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION.out.objects
    versions = BIOC_ALPHAMISSENSER_PROTEIN_STRUCTURE_VISUALIZATION.out.versions
}
