#!/usr/bin/env nextflow
/*
 * Test workflow for Biomate AI Tools
 * Runs all modules with test data
 */

nextflow.enable.dsl=2

// Include all modules
include { ESMFOLD } from '../esmfold/main'
include { ALPHAFOLD_DB } from '../alphafold/main'
include { BOLTZ } from '../boltz/main'
include { CHAI1 } from '../chai1/main'
include { DRUGCLIP } from '../drugclip/main'
include { PROTREK_SEARCH } from '../protrek/main'
include { PROFAM_SCORE } from '../profam/main'
include { SCFV_DESIGN } from '../scfv-pmpnn/main'
include { SYNCRAFT } from '../syncraft/main'

params.test_data = "${projectDir}"
params.outdir = "${projectDir}/../test_results"
params.test = 'all'  // or specific tool name

workflow TEST_ESMFOLD {
    ch_fasta = Channel.of([[id: 'test_protein'], file("${params.test_data}/test.fasta")])
    ESMFOLD(ch_fasta)
    ESMFOLD.out.pdb.view { "ESMFold output: $it" }
}

workflow TEST_DRUGCLIP {
    ch_target = Channel.of([[id: 'test_target'], file("${params.test_data}/test.fasta")])
    ch_compounds = Channel.fromPath("${params.test_data}/test_compounds.smi")
    DRUGCLIP(ch_target, ch_compounds)
    DRUGCLIP.out.scores.view { "DrugCLIP output: $it" }
}

workflow TEST_BOLTZ {
    ch_fasta = Channel.of([[id: 'test_boltz'], file("${params.test_data}/test.fasta")])
    ch_ligand = Channel.fromPath("${params.test_data}/test_ligand.sdf")
    BOLTZ(ch_fasta, ch_ligand)
    BOLTZ.out.pdb.view { "Boltz output: $it" }
}

workflow TEST_SYNCRAFT {
    ch_smiles = Channel.of([[id: 'aspirin'], 'CC(=O)Oc1ccccc1C(=O)O'])
    SYNCRAFT(ch_smiles)
    SYNCRAFT.out.route.view { "SynCraft output: $it" }
}

workflow {
    // Default: run ESMFold test (API-based, no GPU needed)
    if (params.test == 'all' || params.test == 'esmfold') {
        TEST_ESMFOLD()
    }
    if (params.test == 'all' || params.test == 'drugclip') {
        TEST_DRUGCLIP()
    }
    if (params.test == 'all' || params.test == 'boltz') {
        TEST_BOLTZ()
    }
    if (params.test == 'syncraft') {
        TEST_SYNCRAFT()
    }
}
