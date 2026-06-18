#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSnID — peptide_modification_mapping
// Report peptide modifications, encode them with symbols, map modification sites to protein sequences using a FASTA file, and remap accessions to gene symbols.
// Input: phospho.mzid.gz, for_phospho.fasta.gz
// Container: quay.io/biocontainers/bioconductor-msnid:1.44.0--r45ha27e39d_0
// R packages: Biostrings, MSnID, dplyr, xtable
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, MSnID, dplyr, xtable
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Initialize MSnID and read modification data
//  * 2. [Visualization & Output] Report present modifications and add symbols to represent them
//  * 3. [Input & Preparation] Read FASTA file and map modification sites
//  * 4. [Input & Preparation] Fetch conversion table and remap accessions in both MSnID and FASTA
//  * 5. [Core Analysis] Re-map modification sites using the updated gene symbols

nextflow.enable.dsl = 2

process BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "MSnID", "dplyr", "xtable")
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
    
    library(MSnID)
    library(xtable)
    library(dplyr)
    library(Biostrings)
    
    # 1. Initialize MSnID and read modification data from local files
    m <- MSnID(".")
    mzids <- "phospho.mzid.gz"
    m <- read_mzIDs(m, mzids)
    
    # 2. Report present modifications and add symbols to represent them
    mods_reported <- report_mods(m)
    write.csv(as.data.frame(mods_reported), "reported_mods.csv", row.names = TRUE)
    
    m <- add_mod_symbol(m, mod_mass="79.966330925", symbol="*")
    x1 <- psms(m) %>% 
        distinct(modification, peptide, peptide_mod)
    write.csv(x1, "psms_phospho_symbol.csv", row.names = FALSE)
    
    m <- add_mod_symbol(m, mod_mass="229.1629", symbol="#")
    m <- add_mod_symbol(m, mod_mass="57.021463735", symbol="^")
    x2 <- psms(m) %>% 
        distinct(modification, peptide, peptide_mod)
    write.csv(x2, "psms_all_symbols.csv", row.names = FALSE)
    
    # 3. Read FASTA file and map modification sites
    fst_path <- "for_phospho.fasta.gz"
    fst <- readAAStringSet(fst_path)
    names(fst) <- sub("(^[^ ]*) .*\$", "\\1", names(fst))
    
    m <- map_mod_sites(m, fst, 
                       accession_col = "accession", 
                       peptide_mod_col = "peptide_mod", 
                       mod_char = "*",
                       site_delimiter = "lower")
    
    x3 <- psms(m) %>% 
      distinct(peptide_mod, SiteID)
    write.csv(x3, "mapped_sites_uniprot.csv", row.names = FALSE)
    
    # 4. Fetch conversion table and remap accessions in both MSnID and FASTA
    # Wrapped in tryCatch to handle potential network/AnnotationHub issues gracefully
    tryCatch({
      conv_tab <- fetch_conversion_table("Homo sapiens", "UNIPROT", "SYMBOL")
      write.csv(conv_tab, "conversion_table.csv", row.names = FALSE)
      
      print(head(conv_tab))
      print(head(accessions(m)))
      
      m <- remap_accessions(m, conv_tab, extraction_pttrn = "\\\\|([^|-]+)(-\\\\d+)?\\\\|")
      print(head(accessions(m)))
      
      fst_path_2 <- remap_fasta_entry_names(fst_path, conv_tab, "\\\\|([^|-]+)(-\\\\d+)?\\\\|")
      
      print(readAAStringSet(fst_path))
      print(readAAStringSet(fst_path_2))
      
      # 5. Re-map modification sites using the updated gene symbols
      fst <- readAAStringSet(fst_path_2)
      m <- map_mod_sites(m, fst, 
                         accession_col = "accession", 
                         peptide_mod_col = "peptide_mod", 
                         mod_char = "*",
                         site_delimiter = "lower")
      
      x4 <- psms(m) %>% 
        distinct(peptide_mod, SiteID)
      write.csv(x4, "mapped_sites_symbol.csv", row.names = FALSE)
      
    }, error = function(e) {
      message("Skipping accession remapping due to error (likely offline or AnnotationHub issue): ", e\$message)
    })
    
    # Save the final MSnID object
    saveRDS(m, "msnid_final.rds")
    
    # Clean up cache
    unlink(".Rcache", recursive=TRUE)

    writeLines(c(
        '"BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING":',
        paste0('    MSnID: ', as.character(packageVersion('MSnID')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peptide_modification_mapping.csv versions.yml
    """
}

workflow BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phospho.mzid.gz, for_phospho.fasta.gz ] ]

    main:
    BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING(ch_input)

    emit:
    tables   = BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING.out.tables
    plots    = BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING.out.plots
    objects  = BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING.out.objects
    versions = BIOC_MSNID_PEPTIDE_MODIFICATION_MAPPING.out.versions
}
