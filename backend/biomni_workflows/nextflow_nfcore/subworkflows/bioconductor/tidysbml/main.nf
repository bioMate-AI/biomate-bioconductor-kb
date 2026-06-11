#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tidysbml — tidysbml_genomic_pipeline
// Parse and analyze genomic intervals and metadata by converting them into a structured SBML model and extracting tidy data frames for systems biology analysis.
// Input: regions.bed, coldata.csv
// Container: 1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, S4Vectors, rtracklayer, tidysbml
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # --- Load required libraries ---
    library(tidysbml)
    library(rtracklayer)
    library(GenomicRanges)
    library(S4Vectors)
    library(BiocGenerics)
    
    # --- Import input files from the working directory ---
    message("Reading input genomic intervals and metadata...")
    regions <- rtracklayer::import("regions.bed")
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # --- Construct a valid SBML XML representation from genomic ---
    # We map chromosomes to Compartments, genomic regions to Species, and sequential transitions to Reactions.
    message("Generating SBML model from genomic regions...")
    sbml_lines <- c(
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<sbml xmlns="http://www.sbml.org/sbml/level3/version2/core" level="3" version="2">',
      '  <model id="GenomicRegionsModel">'
    )
    
    # Define Compartments based on unique chromosomes
    sbml_lines <- c(sbml_lines, '    <listOfCompartments>')
    chroms <- unique(as.character(seqnames(regions)))
    if (length(chroms) == 0) {
      chroms <- "chr1"
    }
    for (chr in chroms) {
      sbml_lines <- c(sbml_lines, sprintf('      <compartment id="%s" name="%s" constant="true"/>', chr, chr))
    }
    sbml_lines <- c(sbml_lines, '    </listOfCompartments>')
    
    # Define Species based on genomic regions
    sbml_lines <- c(sbml_lines, '    <listOfSpecies>')
    for (i in seq_along(regions)) {
      reg <- regions[i]
      id <- paste0("reg_", i)
      name <- if (!is.null(reg\$name) && !is.na(reg\$name)) reg\$name else id
      chr <- as.character(seqnames(reg))
      
      sbml_lines <- c(sbml_lines, sprintf('      <species id="%s" name="%s" compartment="%s" hasOnlySubstanceUnits="false" boundaryCondition="false" constant="false">', id, name, chr))
      
      # Add annotations to demonstrate tidysbml's annotation parsing capabilities
      sbml_lines <- c(sbml_lines, '        <annotation>')
      sbml_lines <- c(sbml_lines, '          <bqbiol:is xmlns:bqbiol="http://biomodels.net/biology-qualifiers/">')
      sbml_lines <- c(sbml_lines, '            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">')
      sbml_lines <- c(sbml_lines, sprintf('              <rdf:Description rdf:about="#%s">', id))
      sbml_lines <- c(sbml_lines, '                <bqbiol:is>')
      sbml_lines <- c(sbml_lines, '                  <rdf:Bag>')
      sbml_lines <- c(sbml_lines, sprintf('                    <rdf:li rdf:resource="https://identifiers.org/uniprot/P%05d"/>', i))
      sbml_lines <- c(sbml_lines, '                  </rdf:Bag>')
      sbml_lines <- c(sbml_lines, '                </bqbiol:is>')
      sbml_lines <- c(sbml_lines, '              </rdf:Description>')
      sbml_lines <- c(sbml_lines, '            </rdf:RDF>')
      sbml_lines <- c(sbml_lines, '          </bqbiol:is>')
      sbml_lines <- c(sbml_lines, '        </annotation>')
      sbml_lines <- c(sbml_lines, '      </species>')
    }
    sbml_lines <- c(sbml_lines, '    </listOfSpecies>')
    
    # Define Reactions representing sequential transitions between genomic regions
    sbml_lines <- c(sbml_lines, '    <listOfReactions>')
    if (length(regions) >= 2) {
      for (i in 1:(length(regions) - 1)) {
        rxn_id <- paste0("rxn_", i)
        sbml_lines <- c(sbml_lines, sprintf('      <reaction id="%s" reversible="false" fast="false">', rxn_id))
        sbml_lines <- c(sbml_lines, '        <listOfReactants>')
        sbml_lines <- c(sbml_lines, sprintf('          <speciesReference species="reg_%d" constant="true"/>', i))
        sbml_lines <- c(sbml_lines, '        </listOfReactants>')
        sbml_lines <- c(sbml_lines, '        <listOfProducts>')
        sbml_lines <- c(sbml_lines, sprintf('          <speciesReference species="reg_%d" constant="true"/>', i + 1))
        sbml_lines <- c(sbml_lines, '        </listOfProducts>')
        sbml_lines <- c(sbml_lines, '      </reaction>')
      }
    } else {
      sbml_lines <- c(sbml_lines, '      <reaction id="rxn_1" reversible="false" fast="false">',
                                  '        <listOfReactants>',
                                  '          <speciesReference species="reg_1" constant="true"/>',
                                  '        </listOfReactants>',
                                  '      </reaction>')
    }
    sbml_lines <- c(sbml_lines, '    </listOfReactions>')
    sbml_lines <- c(sbml_lines, '  </model>', '</sbml>')
    
    sbml_file <- "generated_model.sbml"
    writeLines(sbml_lines, sbml_file)
    message("SBML model written to: ", sbml_file)
    
    # --- Validate the generated SBML file ---
    message("Validating SBML file...")
    validation_status <- tryCatch({
      tidysbml::sbml_validate(sbml_file)
    }, error = function(e) {
      message("Validation function returned an error or is not supported: ", e\$message)
      NULL
    })
    
    # --- Convert SBML to R list and extract tidy data frames ---
    message("Converting SBML to R list and extracting data frames...")
    sbml_list <- tidysbml::sbml_as_list(sbml_file)
    list_of_dfs <- tidysbml::as_dfs(sbml_list, type = "list")
    
    # Extract individual data frames safely
    df_compartments <- NULL
    df_species <- NULL
    df_reactions <- NULL
    df_species_in_reactions <- NULL
    
    if (!is.null(list_of_dfs)) {
      if ("df_compartments" %in% names(list_of_dfs)) {
        df_compartments <- list_of_dfs\$df_compartments
      } else if (length(list_of_dfs) >= 1) {
        df_compartments <- list_of_dfs[[1]]
      }
      
      if ("df_species" %in% names(list_of_dfs)) {
        df_species <- list_of_dfs\$df_species
      } else if (length(list_of_dfs) >= 2) {
        df_species <- list_of_dfs[[2]]
      }
      
      if ("df_reactions" %in% names(list_of_dfs)) {
        df_reactions <- list_of_dfs\$df_reactions
      } else if (length(list_of_dfs) >= 3) {
        df_reactions <- list_of_dfs[[3]]
      }
      
      if ("df_species_in_reactions" %in% names(list_of_dfs)) {
        df_species_in_reactions <- list_of_dfs\$df_species_in_reactions
      } else if (length(list_of_dfs) >= 4) {
        df_species_in_reactions <- list_of_dfs[[4]]
      }
    }
    
    # Fallback to single-component extraction if as_dfs was incomplete
    if (is.null(df_species)) {
      message("Extracting species dataframe individually...")
      list_species <- tidysbml::sbml_as_list(sbml_file, component = "species")
      df_species <- tidysbml::as_df(list_species)
    }
    
    if (is.null(df_reactions) || is.null(df_species_in_reactions)) {
      message("Extracting reactions dataframes individually...")
      list_react <- tidysbml::sbml_as_list(sbml_file, component = "reactions")
      dfs_about_reactions <- tidysbml::as_df(list_react)
      if (is.list(dfs_about_reactions)) {
        if (length(dfs_about_reactions) >= 1) df_reactions <- dfs_about_reactions[[1]]
        if (length(dfs_about_reactions) >= 2) df_species_in_reactions <- dfs_about_reactions[[2]]
      }
    }
    
    # --- Extract and process annotations ---
    message("Processing annotations from species data frame...")
    mapped_annotations <- data.frame(species_id = character(), annotation_uri = character(), uniprot_id = character(), stringsAsFactors = FALSE)
    
    if (!is.null(df_species) && "annotation_is" %in% colnames(df_species)) {
      uris <- na.omit(unlist(lapply(df_species\$annotation_is, function(x) {
        unlist(strsplit(x, "||", fixed = TRUE))
      })))
      
      if (length(uris) > 0) {
        uniprot_uris <- uris[grepl("uniprot", uris)]
        if (length(uniprot_uris) > 0) {
          uniprot_ids <- vapply(uniprot_uris, function(x) {
            parts <- unlist(strsplit(x, "/"))
            parts[length(parts)]
          }, FUN.VALUE = character(1))
          
          mapped_annotations <- data.frame(
            species_id = df_species\$id[seq_along(uniprot_uris)],
            annotation_uri = uniprot_uris,
            uniprot_id = uniprot_ids,
            row.names = NULL,
            stringsAsFactors = FALSE
          )
        }
      }
    }
    
    # --- Write all outputs to CSV files ---
    message("Writing output tables...")
    write.csv(df_compartments, "sbml_compartments.csv", row.names = FALSE)
    write.csv(df_species, "sbml_species.csv", row.names = FALSE)
    write.csv(df_reactions, "sbml_reactions.csv", row.names = FALSE)
    write.csv(df_species_in_reactions, "sbml_species_in_reactions.csv", row.names = FALSE)
    write.csv(mapped_annotations, "mapped_annotations.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE":',
        paste0('    tidysbml: ', as.character(packageVersion('tidysbml')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidysbml_genomic_pipeline.csv versions.yml
    """
}

workflow BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE.out.tables
    plots    = BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE.out.plots
    objects  = BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE.out.objects
    versions = BIOC_TIDYSBML_TIDYSBML_GENOMIC_PIPELINE.out.versions
}
