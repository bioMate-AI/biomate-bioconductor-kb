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
//  * 1. [Visualization & Output] Load source and target annotation files and the HomoloGene database. 2. Map source probe sets to Entrez Gene IDs. 3. Find target s

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
    
    # 1. Load source and target annotation files and the HomoloGene database
    annotation_HGU133Plus2 <- read.csv('HG-U133_Plus_2_annot.csv',
                                       colClasses = 'character', comment.char = '#')
    annotation_Mouse4302 <- read.csv('Mouse430_2_annot.csv',
                                     colClasses = 'character', comment.char = '#')
    homologene <- read.delim('homologene.data', header = FALSE)
    target_species <- 10090
    
    # 2. Map source probe sets to Entrez Gene IDs
    ps_HGU133Plus2 <- annotation_HGU133Plus2[, 1]
    gid_HGU133Plus2 <- getGENEID(ps_HGU133Plus2, annotation_HGU133Plus2)
    length_gid_HGU133Plus2 <- sapply(gid_HGU133Plus2, function(x) { length(x) })
    
    # 3. Find target species orthologous Gene IDs using getHOMOLOG
    gid_Mouse4302 <- getHOMOLOG(unlist(gid_HGU133Plus2), target_species, homologene)
    length_gid_Mouse4302 <- sapply(gid_Mouse4302, function(x) { length(x) })
    
    # 4. Map target Gene IDs to target probe sets using getPROBESET
    ps_Mouse4302 <- getPROBESET(unlist(gid_Mouse4302), annotation_Mouse4302)
    
    # 5. Compact and clean the mapped lists using compactList to handle multi-mapping
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
    
    # 6. Combine and write the final mapping table to a text file
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
