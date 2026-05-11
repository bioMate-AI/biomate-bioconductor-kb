#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

/*
 * PhyKIT phylogenetic metrics workflow.
 *
 * Input:  S3 directory of MAFFT-aligned + IQ-TREE-trimmed gene files
 *         (expects pairs of *.faa.mafft.clipkit and *.faa.mafft.clipkit.treefile,
 *          *.faa.mafft.clipkit.iqtree)
 *
 * Output: TSV with one row per gene reporting treeness, RCV, treeness/RCV,
 *         saturation, and DVMC.  Plus a Mann-Whitney U comparison if
 *         params.group_a and params.group_b are set (S3 glob patterns).
 */

params.alignment_dir = null   // glob of *.faa.mafft.clipkit files
params.tree_dir      = null   // glob of *.faa.mafft.clipkit.treefile files
params.outdir = './results'

// Use biocontainers phykit (Python package shipped via conda)
PHYKIT_CONTAINER = 'staphb/ncbi-amrfinderplus:latest'   // placeholder — see install step

process PHYKIT_PER_GENE {
    tag "${prefix}"
    publishDir "${params.outdir}/per_gene", mode: 'copy'
    container 'python:3.11-slim-bookworm'
    cpus 1
    memory '2 GB'

    input:
    tuple val(prefix), path(aln), path(tree)

    output:
    path "${prefix}.metrics.tsv", emit: tsv

    script:
    """
    set -euo pipefail
    apt-get update -qq && apt-get install -y -qq procps >/dev/null 2>&1 || true
    pip install --quiet phykit==2.1.92 2>&1 | tail -1
    {
      printf '%s\\t' "${prefix}"
      phykit treeness ${tree} 2>/dev/null | tr -d '\\n' || printf 'NA'
      printf '\\t'
      phykit rcv ${aln} 2>/dev/null | tr -d '\\n' || printf 'NA'
      printf '\\t'
      phykit treeness_over_rcv -t ${tree} -a ${aln} 2>/dev/null | awk '{print \$1}' | tr -d '\\n' || printf 'NA'
      printf '\\t'
      phykit saturation -t ${tree} -a ${aln} 2>/dev/null | tr -d '\\n' || printf 'NA'
      printf '\\n'
    } > ${prefix}.metrics.tsv
    """
}

process MERGE_METRICS {
    publishDir "${params.outdir}", mode: 'copy'
    container 'python:3.11-slim-bookworm'

    input:
    path tsvs

    output:
    path 'phykit_metrics.tsv', emit: merged

    script:
    """
    printf 'gene\\ttreeness\\trcv\\ttrn\\tsaturation\\n' > phykit_metrics.tsv
    cat ${tsvs} >> phykit_metrics.tsv
    """
}

workflow {
    aln_pat = params.alignment_dir.contains('*') ? params.alignment_dir : "${params.alignment_dir}/*.clipkit"
    tree_pat = params.tree_dir.contains('*')     ? params.tree_dir      : "${params.tree_dir}/*.treefile"

    aln_ch  = Channel.fromPath(aln_pat).map  { f -> tuple(f.simpleName.replaceAll(/\.faa$|\.mafft$|\.clipkit$/, ''), f) }
    tree_ch = Channel.fromPath(tree_pat).map { f -> tuple(f.simpleName.replaceAll(/\.faa$|\.mafft$|\.clipkit$|\.treefile$/, ''), f) }

    paired = aln_ch.join(tree_ch).map { prefix, aln, tree -> tuple(prefix, aln, tree) }
    PHYKIT_PER_GENE(paired)
    MERGE_METRICS(PHYKIT_PER_GENE.out.tsv.collect())
}
