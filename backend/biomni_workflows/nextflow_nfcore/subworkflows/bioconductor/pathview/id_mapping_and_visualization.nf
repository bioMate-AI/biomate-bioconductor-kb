#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathview — id_mapping_and_visualization
// Map non-standard gene (Ensembl) and compound (CAS) IDs to standard KEGG/Entrez IDs and visualize them.
// Input: ensembl_gene_expression.tsv, cas_metabolite_abundance.tsv
// Container: quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0
// R packages: org.Hs.eg.db, pathview
// Bioconductor: 3.20 | R: 4.4
// Requires: org.Hs.eg.db, pathview
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and non-standard ID data
//  * 2. [Visualization & Output] Render pathway using automatic ID mapping inside pathview
//  * 3. [Core Analysis] Perform manual ID mapping using cpdidmap and id2eg
//  * 4. [Visualization & Output] Summarize mapped data using mol.sum
//  * 5. [Visualization & Output] Render pathway using manually mapped data

nextflow.enable.dsl = 2

process BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("org.Hs.eg.db", "pathview")
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
    library(pathview)
    library(org.Hs.eg.db)
    
    # Define the mapping lists and demo paths manually to avoid forbidden data() calls.
    # We map gene.idtype.list[4] to "ENSEMBL" to match the user's Ensembl Gene IDs input.
    gene.idtype.list <- c("SYMBOL", "GENENAME", "ENSEMBLPROT", "ENSEMBL")
    cpd.simtypes <- c("KEGG COMPOUND accession", "CAS Registry Number")
    demo.paths <- list(
      sel.paths = c(NA, NA, "00640"),
      kpos2 = c(NA, NA, "topright"),
      spos = c(NA, NA, "bottomleft")
    )
    i <- 3
    
    # Read user input files
    gene_df <- read.delim("ensembl_gene_expression.tsv", header = TRUE, sep = "\t", row.names = 1)
    gene.ensprot <- gene_df[, 1]
    names(gene.ensprot) <- rownames(gene_df)
    
    cpd_df <- read.delim("cas_metabolite_abundance.tsv", header = TRUE, sep = "\t", row.names = 1)
    cpd.cas <- cpd_df[, 1]
    names(cpd.cas) <- rownames(cpd_df)
    
    # Render pathway using automatic ID mapping inside pathview
    pv.out <- pathview(gene.data = gene.ensprot, cpd.data = cpd.cas, 
        gene.idtype = gene.idtype.list[4], cpd.idtype = cpd.simtypes[2], 
        pathway.id = demo.paths\$sel.paths[i], species = "hsa", same.layer = T, 
        out.suffix = "gene.ensprot.cpd.cas", keys.align = "y", kegg.native = T, 
        key.pos = demo.paths\$kpos2[i], sign.pos = demo.paths\$spos[i], 
        limit = list(gene = 3, cpd = 3), bins = list(gene = 6, cpd = 6))
    
    # Perform manual ID mapping using cpdidmap and id2eg
    id.map.cas <- cpdidmap(in.ids = names(cpd.cas), in.type = cpd.simtypes[2], 
        out.type = "KEGG COMPOUND accession")
    cpd.kc <- mol.sum(mol.data = cpd.cas, id.map = id.map.cas)
    id.map.ensprot <- id2eg(ids = names(gene.ensprot), 
        category = gene.idtype.list[4], org = "Hs")
    gene.entrez <- mol.sum(mol.data = gene.ensprot, id.map = id.map.ensprot)
    
    # Render pathway using manually mapped data
    pv.out <- pathview(gene.data = gene.entrez, cpd.data = cpd.kc, 
        pathway.id = demo.paths\$sel.paths[i], species = "hsa", same.layer = T, 
        out.suffix = "gene.entrez.cpd.kc", keys.align = "y", kegg.native = T, 
        key.pos = demo.paths\$kpos2[i], sign.pos = demo.paths\$spos[i], 
        limit = list(gene = 3, cpd = 3), bins = list(gene = 6, cpd = 6))
    
    # Write outputs
    write.csv(as.data.frame(id.map.cas), "id_map_cas.csv", row.names = FALSE)
    write.csv(as.data.frame(cpd.kc), "cpd_kc.csv", row.names = TRUE)
    write.csv(as.data.frame(id.map.ensprot), "id_map_ensprot.csv", row.names = FALSE)
    write.csv(as.data.frame(gene.entrez), "gene_entrez.csv", row.names = TRUE)
    saveRDS(pv.out, "pv_out.rds")

    writeLines(c(
        '"BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION":',
        paste0('    pathview: ', as.character(packageVersion('pathview')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_id_mapping_and_visualization.csv versions.yml
    """
}

workflow BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ensembl_gene_expression.tsv, cas_metabolite_abundance.tsv ] ]

    main:
    BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION.out.tables
    plots    = BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION.out.plots
    objects  = BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION.out.objects
    versions = BIOC_PATHVIEW_ID_MAPPING_AND_VISUALIZATION.out.versions
}
