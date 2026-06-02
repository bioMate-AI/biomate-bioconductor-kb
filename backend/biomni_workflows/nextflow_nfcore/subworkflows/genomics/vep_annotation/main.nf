#!/usr/bin/env nextflow
/*
 * genomics/vep_annotation
 *
 * Variant Effect Prediction using Ensembl VEP.
 * Annotates VCF files with functional consequences, population frequencies
 * (gnomAD), clinical significance (ClinVar), and CADD/SpliceAI scores.
 *
 * Pipeline Steps:
 * 1. VEP                -- Ensembl VEP offline annotation
 * 2. FILTER_VEP         -- Filter for high/moderate impact variants
 * 3. PARSE_VEP          -- Parse CSQ fields into tabular TSV
 *
 * Outputs:
 *   annotated.vcf.gz           -- VEP-annotated VCF (gzip compressed)
 *   annotated_variants.tsv     -- Tabular variant table
 *   high_impact_variants.vcf.gz -- Filtered high/moderate impact VCF
 *   vep_stats.html             -- VEP summary statistics
 *
 * References:
 *   McLaren et al. Genome Biology 2016, 17:122
 */

nextflow.enable.dsl = 2

params.input              = null          // VCF or VCF.GZ file to annotate
params.genome             = 'GRCh38'
params.species            = 'homo_sapiens'
params.assembly           = 'GRCh38'
params.vep_cache          = '/vep_cache'
params.vep_cache_version  = '110'

params.gnomad             = true
params.clinvar            = true
params.cadd               = false
params.cadd_snvs          = null
params.cadd_indels        = null
params.spliceai           = false
params.spliceai_snvs      = null
params.spliceai_indels    = null

params.filter_impact      = 'HIGH,MODERATE'
params.af_max             = 0.01

params.outdir             = './results/vep_annotation'
params.publish_dir_mode   = 'copy'
params.max_memory         = '32.GB'
params.max_cpus           = 8
params.max_time           = '24.h'

process VEP {
    tag "${meta.id}"
    container 'ensemblorg/ensembl-vep:release_110.0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(vcf)

    output:
    tuple val(meta), path("${meta.id}.vep.vcf.gz"),     emit: vcf
    tuple val(meta), path("${meta.id}.vep.vcf.gz.tbi"), emit: tbi
    path("${meta.id}_vep_stats.html"),                   emit: stats

    script:
    def plugins = []
    if (params.cadd && params.cadd_snvs)
        plugins << "CADD,${params.cadd_snvs},${params.cadd_indels}"
    if (params.spliceai && params.spliceai_snvs)
        plugins << "SpliceAI,snv=${params.spliceai_snvs},indel=${params.spliceai_indels}"
    def plugin_args  = plugins.collect { "--plugin ${it}" }.join(" ")
    def gnomad_arg   = params.gnomad  ? "--af_gnomad --max_af" : ""
    def clinvar_arg  = params.clinvar ? "--check_existing"     : ""
    """
    vep \\
        --input_file ${vcf} --output_file ${meta.id}.vep.vcf \\
        --format vcf --vcf \\
        --symbol --numbers --biotype --hgvs --hgvsg \\
        --sift b --polyphen b --canonical --mane --mane_select \\
        --species ${params.species} --assembly ${params.assembly} \\
        --cache --offline --cache_version ${params.vep_cache_version} \\
        --dir_cache ${params.vep_cache} \\
        --fork ${task.cpus} --stats_file ${meta.id}_vep_stats.html \\
        --no_progress ${gnomad_arg} ${clinvar_arg} ${plugin_args}
    bgzip ${meta.id}.vep.vcf
    tabix -p vcf ${meta.id}.vep.vcf.gz
    """
}

process FILTER_VEP {
    tag "${meta.id}"
    container 'ensemblorg/ensembl-vep:release_110.0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(vcf)

    output:
    tuple val(meta), path("${meta.id}.high_impact.vcf.gz"), emit: filtered_vcf

    script:
    """
    filter_vep --input_file ${vcf} --output_file ${meta.id}.high_impact.vcf \\
        --filter "IMPACT in ${params.filter_impact}"
    bgzip ${meta.id}.high_impact.vcf
    """
}

process PARSE_VEP {
    tag "${meta.id}"
    container 'quay.io/biocontainers/htslib:1.19.1--h81da01d_0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(vcf)

    output:
    tuple val(meta), path("${meta.id}_annotated_variants.tsv"), emit: tsv

    script:
    """
    python3 - <<'PYEOF'
import gzip, re

csq_fields = []
rows = []
with gzip.open("${vcf}", "rt") as fh:
    for line in fh:
        if line.startswith("##INFO=<ID=CSQ"):
            m = re.search(r'Format: ([^"]+)"', line)
            if m: csq_fields = m.group(1).split("|")
        elif line.startswith("#"):
            continue
        else:
            parts = line.rstrip().split("\t")
            chrom, pos, vid, ref, alt, qual, filt, info = parts[:8]
            for allele in re.findall(r'CSQ=([^;]+)', info)[0:1]:
                for csq in allele.split(","):
                    vals = csq.split("|")
                    row = {"CHROM":chrom,"POS":pos,"ID":vid,"REF":ref,"ALT":alt}
                    row.update(dict(zip(csq_fields, vals+[""]*(len(csq_fields)-len(vals)))))
                    rows.append(row)

cols = list(rows[0].keys()) if rows else ["CHROM","POS","ID","REF","ALT"]
with open("${meta.id}_annotated_variants.tsv","w") as out:
    out.write("\t".join(cols)+"\n")
    for r in rows:
        out.write("\t".join(str(r.get(c,"")) for c in cols)+"\n")
PYEOF
    """
}

workflow {
    Channel.fromPath(params.input)
        .map { vcf -> [[id: vcf.baseName.replaceAll(/\.vcf.*/, '')], vcf] }
        .set { vcf_ch }
    VEP(vcf_ch)
    FILTER_VEP(VEP.out.vcf)
    PARSE_VEP(VEP.out.vcf)
}
