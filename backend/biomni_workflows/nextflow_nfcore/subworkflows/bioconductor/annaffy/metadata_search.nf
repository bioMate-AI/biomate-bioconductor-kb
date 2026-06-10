#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: annaffy — metadata_search
// Search Affymetrix chip annotation metadata using text queries or Gene Ontology identifiers to find matching probe IDs.
// Input: hgu95av2.db
// Container: quay.io/biocontainers/bioconductor-annaffy:1.82.0--r45hdfd78af_0
// R packages: annaffy, hgu95av2.db
// Bioconductor: 3.20 | R: 4.4
// Requires: annaffy, hgu95av2.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the annotation database package
//  * 2. [Core Analysis] Perform text searches on specific metadata columns (e.g., Description, Pathway, GenBank) using aafSearchText()
//  * 3. [Core Analysis] Perform Gene Ontology searches using GO IDs (numeric or character) with aafSearchGO()

nextflow.enable.dsl = 2

process BIOC_ANNAFFY_METADATA_SEARCH {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("annaffy", "hgu95av2.db")
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
    
    # 1. Load the annotation database package and annaffy
    if (dir.exists("hgu95av2.db")) {
      # If hgu95av2.db is provided as a package directory in the working directory
      install.packages("hgu95av2.db", repos = NULL, type = "source", quiet = TRUE)
    } else if (file.exists("hgu95av2.db")) {
      # If hgu95av2.db is provided as a tarball file
      install.packages("hgu95av2.db", repos = NULL, type = "source", quiet = TRUE)
    }
    
    library(annaffy)
    library(hgu95av2.db)
    
    # 2. Perform text searches on specific metadata columns using aafSearchText()
    kinases <- aafSearchText("hgu95av2.db", "Description", "kinase")
    writeLines(kinases, "kinases.txt")
    
    probes <- aafSearchText("hgu95av2.db", c("Description", "Pathway"), c("ribosome", "polymerase"))
    writeLines(probes, "probes_ribosome_polymerase.txt")
    
    probes <- aafSearchText("hgu95av2.db", "Description", c("DNA", "polymerase"), logic = "AND")
    writeLines(probes, "probes_dna_polymerase.txt")
    
    gbs <- c("AF035121", "AL021546", "AJ006123", "AL080082", "AI289489")
    gbs_results <- aafSearchText("hgu95av2.db", "GenBank", gbs)
    writeLines(gbs_results, "probes_genbank.txt")
    
    # 3. Perform Gene Ontology searches using GO IDs with aafSearchGO()
    go_results1 <- aafSearchGO("hgu95av2.db", c("GO:0000002", "GO:0000008"))
    writeLines(go_results1, "probes_go_1.txt")
    
    go_results2 <- aafSearchGO("hgu95av2.db", c("2", "8"))
    writeLines(go_results2, "probes_go_2.txt")
    
    go_results3 <- aafSearchGO("hgu95av2.db", c(2, 8))
    writeLines(go_results3, "probes_go_3.txt")
    
    # Save consolidated results as an RDS object
    all_results <- list(
      kinases = kinases,
      probes_ribosome_polymerase = readLines("probes_ribosome_polymerase.txt"),
      probes_dna_polymerase = probes,
      probes_genbank = gbs_results,
      probes_go_1 = go_results1,
      probes_go_2 = go_results2,
      probes_go_3 = go_results3
    )
    saveRDS(all_results, "metadata_search_results.rds")

    writeLines(c(
        '"BIOC_ANNAFFY_METADATA_SEARCH":',
        paste0('    annaffy: ', as.character(packageVersion('annaffy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metadata_search.csv versions.yml
    """
}

workflow BIOC_ANNAFFY_METADATA_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hgu95av2.db ] ]

    main:
    BIOC_ANNAFFY_METADATA_SEARCH(ch_input)

    emit:
    tables   = BIOC_ANNAFFY_METADATA_SEARCH.out.tables
    plots    = BIOC_ANNAFFY_METADATA_SEARCH.out.plots
    objects  = BIOC_ANNAFFY_METADATA_SEARCH.out.objects
    versions = BIOC_ANNAFFY_METADATA_SEARCH.out.versions
}
