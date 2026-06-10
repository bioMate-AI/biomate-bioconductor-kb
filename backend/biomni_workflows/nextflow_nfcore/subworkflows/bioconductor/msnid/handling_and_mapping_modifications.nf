#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msnid — handling_and_mapping_modifications
// Read modified peptide search results, encode modification masses with symbols, map modification sites to protein sequences, and remap accessions to gene symbols
// Input: phospho.mzid.gz, for_phospho.fasta.gz
// Container: quay.io/biocontainers/bioconductor-msnid:1.44.0--r45ha27e39d_0
// R packages: Biostrings, MSnID, dplyr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msnid:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biostrings", "MSnID", "dplyr")
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
    library(MSnID)
    library(dplyr)
    library(Biostrings)
    
    # 1. Load modified PSM data
    # Initialize MSnID object with the current directory as the cache directory
    m <- MSnID(".")
    
    # Define input files (must be in the working directory)
    mzid_path <- "phospho.mzid.gz"
    fasta_path <- "for_phospho.fasta.gz"
    
    # Read mzIdentML search results
    m <- read_mzIDs(m, mzid_path)
    
    # 2. Report present modification masses
    reported_mods <- report_mods(m)
    write.csv(as.data.frame(reported_mods), "reported_modifications.csv", row.names = TRUE)
    
    # 3. Encode modifications with symbols
    # Encode phosphorylation (79.966330925) with "*"
    m <- add_mod_symbol(m, mod_mass="79.966330925", symbol="*")
    x1 <- psms(m) %>% 
        distinct(modification, peptide, peptide_mod)
    write.csv(x1, "encoded_mods_step1.csv", row.names = FALSE)
    
    # Encode other modifications
    m <- add_mod_symbol(m, mod_mass="229.1629", symbol="#")
    m <- add_mod_symbol(m, mod_mass="57.021463735", symbol="^")
    x2 <- psms(m) %>% 
        distinct(modification, peptide, peptide_mod)
    write.csv(x2, "encoded_mods_step2.csv", row.names = FALSE)
    
    # 4. Map modification sites to FASTA sequences
    fst <- readAAStringSet(fasta_path)
    names(fst) <- sub("(^[^ ]*) .*\$", "\\1", names(fst))
    
    m <- map_mod_sites(m, fst, 
                       accession_col = "accession", 
                       peptide_mod_col = "peptide_mod", 
                       mod_char = "*",
                       site_delimiter = "lower")
    
    x3 <- psms(m) %>% 
      distinct(peptide_mod, SiteID)
    write.csv(x3, "mapped_sites_uniprot.csv", row.names = FALSE)
    
    # 5. Remap accession IDs and FASTA entry names to gene symbols
    # Wrap in tryCatch in case of network/AnnotationHub issues
    tryCatch({
      conv_tab <- fetch_conversion_table("Homo sapiens", "UNIPROT", "SYMBOL")
      write.csv(conv_tab, "conversion_table.csv", row.names = FALSE)
      
      # Remap accessions in MSnID object
      m <- remap_accessions(m, conv_tab, extraction_pttrn = "\\|([^|-]+)(-\\d+)?\\|")
      
      # Remap FASTA entry names
      fst_path_2 <- remap_fasta_entry_names(fasta_path, conv_tab, "\\|([^|-]+)(-\\d+)?\\|")
      
      # 6. Re-map modification sites using updated gene symbols
      fst_mapped <- readAAStringSet(fst_path_2)
      m <- map_mod_sites(m, fst_mapped, 
                         accession_col = "accession", 
                         peptide_mod_col = "peptide_mod", 
                         mod_char = "*",
                         site_delimiter = "lower")
      
      x4 <- psms(m) %>% 
        distinct(peptide_mod, SiteID)
      write.csv(x4, "mapped_sites_genesymbol.csv", row.names = FALSE)
    }, error = function(e) {
      message("Warning: Accession remapping to gene symbols failed. Error: ", e\$message)
    })
    
    # Save the final MSnID object
    saveRDS(m, "msnid_final.rds")
    
    # Clean up cache
    unlink(".Rcache", recursive=TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS":
        msnid: \$(Rscript -e 'cat(as.character(packageVersion("msnid")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_handling_and_mapping_modifications.csv versions.yml
    """
}

workflow BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phospho.mzid.gz, for_phospho.fasta.gz ] ]

    main:
    BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS(ch_input)

    emit:
    tables   = BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS.out.tables
    plots    = BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS.out.plots
    objects  = BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS.out.objects
    versions = BIOC_MSNID_HANDLING_AND_MAPPING_MODIFICATIONS.out.versions
}
