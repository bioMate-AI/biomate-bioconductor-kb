#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gwascat
// Represent and model data in the EMBL-EBI GWAS catalog.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gwascat/inst/doc/gwascat.R
// Upstream  : GenomeInfoDb, Gviz, dplyr, ggbio, rtracklayer
// Downstream: vtpnet, liftOver
//
// Install: BiocManager::install("gwascat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GWASCAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gwascat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gwascat:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gwascat:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gwascat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gwascat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gwascat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gwascat)
    library(jsonlite)


    # --- Dotidy [] ---
    # Key functions: get_cached_gwascat, arrange, as_GRanges, keepStandardChromosomes, seqlevels, seqinfo, coarse, args
    gwcat = get_cached_gwascat()
    library(dplyr)
    gwcat |> arrange(DATE)
    gg = gwcat |> as_GRanges()
    gg
    library(GenomeInfoDb)
    data(si.hs.38)
    gg = keepStandardChromosomes(gg, pruning="coarse")
    seqlevels(gg) = seqlevels(si.hs.38)
    seqinfo(gg) = si.hs.38
    gg
    args(get_cached_gwascat)
    args(process_gwas_dataframe)

    # --- Lk1 [] ---
    # Key functions: search, detach, gwascat, objects, topTraits, subsetByTraits
    if (length(grep("gwascat", search()))>0) detach("package:gwascat")
    library(gwascat)
    objects("package:gwascat")
    data(ebicat_2020_04_30)
    gwtrunc = ebicat_2020_04_30
    topTraits(gwtrunc)
    subsetByTraits(gwtrunc, tr="LDL cholesterol")[1:3]

    # --- Lkm [] ---
    # Key functions: requireNamespace, mcols, ifelse, seqlevelsStyle, seqlevels, seqnames, chr, chr4
    requireNamespace("S4Vectors")
    mcols = S4Vectors::mcols
    mlpv = mcols(gwtrunc)$PVALUE_MLOG
    mlpv = ifelse(mlpv > 25, 25, mlpv)
    S4Vectors::mcols(gwtrunc)$PVALUE_MLOG = mlpv
    library(GenomeInfoDb)
    # seqlevelsStyle(gwtrunc) = "UCSC" # no more!
    seqlevels(gwtrunc) = paste0("chr", seqlevels(gwtrunc))
    gwlit = gwtrunc[ which(as.character(seqnames(gwtrunc)) %in% c("chr4", "chr5", "chr6")) ]
    library(ggbio)
    autoplot(gwlit, geom="point", aes(y=PVALUE_MLOG), xlab="chr4-chr6")
    traitsManh(gwtrunc)
    gffpath = system.file("gff3/chr17_43000000_45000000.gff3", package="gwascat")
    library(rtracklayer)
    c17tg = import(gffpath)
    c17td = c17tg[ which(S4Vectors::mcols(c17tg)$type == "Degner_dsQTL") ]
    library(Gviz)
    dsqs = DataTrack( c17td, chrom="chr17", genome="hg19", data="score",
      name="dsQTL")

    # --- Dost [] ---
    # Key functions: GRanges, IRanges, gwcex2gviz, chr17, mcols, AnnotationTrack, displayPars, Stranger_eqtl
    g2 = GRanges(seqnames="chr17", IRanges(start=4.3e7, width=2e6))

    basic = gwcex2gviz(basegr = gwtrunc, contextGR=g2, plot.it=FALSE)
    c17ts = c17tg[ which(S4Vectors::mcols(c17tg)$type == "Stranger_eqtl") ]
    eqloc = AnnotationTrack(c17ts,  chrom="chr17", genome="hg19", name="Str eQTL")
    displayPars(eqloc)$col = "black"
    displayPars(dsqs)$col = "red"
    integ = list(basic[[1]], eqloc, dsqs, basic[[2]], basic[[3]])
    plotTracks(integ)
    data(locon6)
    rson6 = as.character(locon6[[1]])
    rson6[1:5]
    intr = gwtrunc[ intersect(getRsids(gwtrunc), rson6) ]
    sort(table(getTraits(intr)), decreasing=TRUE)[1:10]

    # --- Lkexp [] ---
    # Key functions: GRanges, ifelse, IRanges, mcols, seqlevels, chr, function, suppressWarnings
    #gr6.0 = GRanges(seqnames=ifelse(is.na(locon6$chrom),0,locon6$chrom), 
    #       IRanges(ifelse(is.na(locon6$phys),1,locon6$phys), width=1))
    #S4Vectors::mcols(gr6.0)$rsid = as.character(locon6$dbsnp_rs_id)
    #seqlevels(gr6.0) = paste("chr", seqlevels(gr6.0), sep="")
    data(gr6.0_hg38)
    ag = function(x) as(x, "GRanges")
    ovraw = suppressWarnings(subsetByOverlaps(ag(gwtrunc), gr6.0_hg38))
    length(ovraw)
    ovaug = suppressWarnings(subsetByOverlaps(ag(gwtrunc+500), gr6.0_hg38))
    length(ovaug)
    rawrs = mcols(ovraw)$SNPS
    augrs = mcols(ovaug)$SNPS
    gwtrunc[augrs]
    nn = setdiff( getTraits(gwtrunc[augrs]), getTraits(gwtrunc[rawrs]) )
    length(nn)
    head(nn)
    tail(nn)
    data(gg17N) # translated from GGdata chr 17 calls using ABmat2nuc
    gg17N[1:5,1:5]

    # --- Dorun [] ---
    # Key functions: riskyAlleleCount, ch17, mcols, DataFrame, unlist, mget, mappedkeys, match
    h17 = riskyAlleleCount(gg17N, matIsAB=FALSE, chr="ch17",
     gwwl = gwtrunc)
    h17[1:5,1:5]
    table(as.numeric(h17))
    gwr = gwtrunc
    gwr = gwr[colnames(h17),]
    S4Vectors::mcols(gwr) = cbind(mcols(gwr), DataFrame(t(h17)))
    sn = rownames(h17)
    gwr[,c("DISEASE/TRAIT", sn[1:4])]
    library(DO.db)
    DO()
    alltob = unlist(mget(mappedkeys(DOTERM), DOTERM))
    allt = sapply(alltob, Term)
    allt[1:5]
    cattra = mcols(gwtrunc)$`DISEASE/TRAIT`
    mat = match(tolower(cattra), tolower(allt))
    catDO = names(allt)[mat]
    na.omit(catDO)[1:50]
    mean(is.na(catDO))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gwascat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gwascat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gwascat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GWASCAT:", paste0("    gwascat: ", packageVersion("gwascat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwascat_results.csv
    touch ${prefix}_gwascat_output.rds
    echo "BIOC_GWASCAT:" > versions.yml
    echo "    gwascat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GWASCAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GWASCAT(ch_input)

    emit:
    results  = BIOC_GWASCAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GWASCAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GWASCAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GWASCAT.out.versions  // channel: path(versions.yml)
}
