#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gwascat — visualize_gwas_catalog_data
// Generate Manhattan plots and integrate GWAS catalog data with other genomic tracks (e.g., eQTLs, dsQTLs) using Gviz.
// Input: c17tg
// Container: quay.io/biocontainers/bioconductor-gwascat:2.42.0--r45hdfd78af_0
// R packages: GenomeInfoDb, Gviz, S4Vectors, ggbio, gwascat, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, Gviz, S4Vectors, ggbio, gwascat, rtracklayer
// Visualizations: autoplot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load GWAS Catalog Data and format
//  * 2. [Visualization & Output] Generate Manhattan plots
//  * 3. [Visualization & Output] Import external GFF3 track data from user input
//  * 4. [Visualization & Output] Convert GWAS catalog data to Gviz tracks
//  * 5. [Visualization & Output] Plot integrated tracks

nextflow.enable.dsl = 2

process BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("GenomeInfoDb", "Gviz", "S4Vectors", "ggbio", "gwascat", "rtracklayer")
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
                
    library(gwascat)
    library(rtracklayer)
    library(Gviz)
    library(ggbio)
    library(S4Vectors)
    library(GenomeInfoDb)
    
    # --- Load GWAS Catalog Data and format ---
    gwtrunc = gwascat_from_AHub()
    
    mlpv = mcols(gwtrunc)\$PVALUE_MLOG
    mlpv = ifelse(mlpv > 25, 25, mlpv)
    S4Vectors::mcols(gwtrunc)\$PVALUE_MLOG = mlpv
    seqlevels(gwtrunc) = paste0("chr", seqlevels(gwtrunc))
    gwlit = gwtrunc[ which(as.character(seqnames(gwtrunc)) %in% c("chr4", "chr5", "chr6")) ]
    
    # --- Generate Manhattan plots ---
    pdf("manhattan_autoplot.pdf", width=10, height=6)
    print(autoplot(gwlit, geom="point", aes(y=PVALUE_MLOG), xlab="chr4-chr6"))
    dev.off()
    
    pdf("manhattan_traits.pdf", width=10, height=6)
    tryCatch({
      traitsManh(gwtrunc)
    }, error = function(e) {
      warning("traitsManh visualization encountered an issue: ", e\$message)
    })
    dev.off()
    
    # --- Import external GFF3 track data from user input ---
    c17tg = import("c17tg", format="gff3")
    c17td = c17tg[ which(S4Vectors::mcols(c17tg)\$type == "Degner_dsQTL") ]
    dsqs = DataTrack( c17td, chrom="chr17", genome="hg19", data="score", name="dsQTL")
    
    # --- Convert GWAS catalog data to Gviz tracks ---
    g2 = GRanges(seqnames="chr17", IRanges(start=4.3e7, width=2e6))
    basic = gwcex2gviz(basegr = gwtrunc, contextGR=g2, plot.it=FALSE)
    c17ts = c17tg[ which(S4Vectors::mcols(c17tg)\$type == "Stranger_eqtl") ]
    eqloc = AnnotationTrack(c17ts,  chrom="chr17", genome="hg19", name="Str eQTL")
    displayPars(eqloc)\$col = "black"
    displayPars(dsqs)\$col = "red"
    integ = list(basic[[1]], eqloc, dsqs, basic[[2]], basic[[3]])
    
    # --- Plot integrated tracks ---
    pdf("integrated_tracks.pdf", width=10, height=8)
    plotTracks(integ)
    dev.off()
    
    # Save processed catalog object
    saveRDS(gwtrunc, "processed_gwtrunc.rds")

    writeLines(c(
        '"BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA":',
        paste0('    gwascat: ', as.character(packageVersion('gwascat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visualize_gwas_catalog_data.csv versions.yml
    """
}

workflow BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ c17tg ] ]

    main:
    BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA(ch_input)

    emit:
    tables   = BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA.out.tables
    plots    = BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA.out.plots
    objects  = BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA.out.objects
    versions = BIOC_GWASCAT_VISUALIZE_GWAS_CATALOG_DATA.out.versions
}
