#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gwascat — visualize_gwas_catalog_data
// Generate Manhattan plots and integrate GWAS catalog data with other genomic tracks (e.g., eQTLs, dsQTLs) using Gviz.
// Input: c17tg
// Container: quay.io/biocontainers/bioconductor-gwascat:2.42.0--r45hdfd78af_0
// Requires: GenomeInfoDb, Gviz, S4Vectors, ggbio, gwascat, rtracklayer
// Visualizations: autoplot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Truncate high p-values and format chromosome names. 2. Generate a basic Manhattan plot using autoplot or traitsManh. 3. Import ext

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
                
    library(gwascat)
    library(rtracklayer)
    library(Gviz)
    library(ggbio)
    library(S4Vectors)
    library(GenomeInfoDb)
    
    # 1. Load GWAS Catalog Data and format
    gwtrunc = gwascat_from_AHub()
    
    mlpv = mcols(gwtrunc)\$PVALUE_MLOG
    mlpv = ifelse(mlpv > 25, 25, mlpv)
    S4Vectors::mcols(gwtrunc)\$PVALUE_MLOG = mlpv
    seqlevels(gwtrunc) = paste0("chr", seqlevels(gwtrunc))
    gwlit = gwtrunc[ which(as.character(seqnames(gwtrunc)) %in% c("chr4", "chr5", "chr6")) ]
    
    # 2. Generate Manhattan plots
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
    
    # 3. Import external GFF3 track data from user input
    c17tg = import("c17tg", format="gff3")
    c17td = c17tg[ which(S4Vectors::mcols(c17tg)\$type == "Degner_dsQTL") ]
    dsqs = DataTrack( c17td, chrom="chr17", genome="hg19", data="score", name="dsQTL")
    
    # 4. Convert GWAS catalog data to Gviz tracks
    g2 = GRanges(seqnames="chr17", IRanges(start=4.3e7, width=2e6))
    basic = gwcex2gviz(basegr = gwtrunc, contextGR=g2, plot.it=FALSE)
    c17ts = c17tg[ which(S4Vectors::mcols(c17tg)\$type == "Stranger_eqtl") ]
    eqloc = AnnotationTrack(c17ts,  chrom="chr17", genome="hg19", name="Str eQTL")
    displayPars(eqloc)\$col = "black"
    displayPars(dsqs)\$col = "red"
    integ = list(basic[[1]], eqloc, dsqs, basic[[2]], basic[[3]])
    
    # 5. Plot integrated tracks
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
