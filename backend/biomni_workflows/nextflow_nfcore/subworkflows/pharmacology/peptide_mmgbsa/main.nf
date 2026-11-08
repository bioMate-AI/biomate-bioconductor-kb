#!/usr/bin/env nextflow

/**
 * pharmacology/peptide_mmgbsa
 *
 * OpenMM single-trajectory MM-GBSA (implicit GBn2, CHARMM36m) on a
 * receptor / cyclic-peptide complex, fanned out ONE PROCESS PER COMPLEX so AWS
 * Batch scores every peptide's binding free energy IN PARALLEL.
 *
 * Per complex CIF the process:
 *   1. splits the complex into receptor.pdb (all chains except the shortest) +
 *      peptide.pdb (the shortest chain; renumbered 1..N)
 *   2. builds 3 PSFs with psfgen — complex, receptor-only, ligand-only — the
 *      cyclic peptide via first='none'/last='none' + a head-to-tail CYCP patch
 *   3. OpenMM GBn2 / CHARMM36m implicit-solvent minimize of the complex (CPU)
 *   4. single-point MM-GBSA:  dG = E_complex - E_receptor - E_ligand
 *
 * Ground truth recipe: research/guangzhou_all_atom/peptide_mmgbsa_run.sh.
 * Forced onto CPU (conda-forge OpenMM's CUDA PTX is newer than typical Batch
 * node drivers; implicit solvent on these small systems is fine on CPU, and
 * minimized single-point MM-GBSA is the recommended protocol for short peptides
 * — Sun PCCP 2019). MM-GBSA is a RELATIVE within-target ranking oracle, not an
 * absolute affinity; entropy is omitted. Trust only ring_closed=true rows.
 *
 * Inputs (params):
 *   params.complexes          glob of complex CIFs (one parallel task each),
 *                             e.g. the cyclic_peptide_cofold outputs
 *   params.charmm_toppar_s3   S3 prefix holding CHARMM36 toppar
 *   params.outdir             output directory (default: 'results')
 *
 * Container: CPU. Reuses the biomni-tools ECR image. HONEST GAP: that image
 * must carry the conda-forge stack openmm + psfgen + parmed + gemmi; if it does
 * not, a dedicated MM-GBSA image must be built + pushed to ECR before this runs
 * (peptide_mmgbsa_run.sh provisions it via `conda create -c conda-forge
 * openmm psfgen parmed gemmi`).
 */

nextflow.enable.dsl = 2

params.complexes        = 'results/cofold/**/*.cif'
params.charmm_toppar_s3 = 's3://knowledge-datasets-1759951976/cyclic_peptide/datasets/charmm36_toppar'
params.outdir           = 'results'

process MMGBSA {
    tag "${pep_id}"
    label 'process_high'
    publishDir { "${params.outdir}/mmgbsa/${pep_id}" }, mode: 'copy'

    // CPU image. Must contain conda-forge openmm + psfgen + parmed + gemmi
    // (see module header — may need a dedicated image built + pushed to ECR).
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    tuple val(pep_id), path(complex_cif)

    output:
    tuple val(pep_id), path("${pep_id}_mmgbsa.json"), emit: results
    path "versions.yml",                              emit: versions

    script:
    """
    export PEP_ID='${pep_id}'
    export CIF='${complex_cif}'

    # Fetch CHARMM36 toppar from our S3 cache (both rtf + prm required by
    # OpenMM's CharmmParameterSet). Fail loud if either is missing.
    mkdir -p toppar
    aws s3 cp '${params.charmm_toppar_s3}/top_all36_prot.rtf' toppar/ --only-show-errors
    aws s3 cp '${params.charmm_toppar_s3}/par_all36m_prot.prm' toppar/ --only-show-errors
    export RTF=toppar/top_all36_prot.rtf
    export PRM=toppar/par_all36m_prot.prm
    test -s "\$RTF" || { echo "FATAL: missing CHARMM36 rtf"; exit 1; }
    test -s "\$PRM" || { echo "FATAL: missing CHARMM36 prm"; exit 1; }

    python3 << 'PYEOF'
import os, json
import gemmi
from psfgen import PsfGen
import openmm as mm
from openmm import app, unit
import parmed as pmd

RTF = os.environ['RTF']; PRM = os.environ['PRM']
CIF = os.environ['CIF']; PEP_ID = os.environ['PEP_ID']

# Force CPU: implicit-solvent MM-GBSA on small peptide complexes runs fine on
# CPU, and conda-forge OpenMM CUDA PTX often outpaces the Batch node driver.
CPU = mm.Platform.getPlatformByName('CPU')
try:
    CPU.setPropertyDefaultValue('Threads', str(os.cpu_count() or 8))
except Exception:
    pass
PLAT = CPU
print('platform:', PLAT.getName(), 'threads', os.cpu_count())

def is_aa(r):
    i = gemmi.find_tabulated_residue(r.name)
    return bool(i) and i.is_amino_acid()

def split_complex(cif, tag):
    # peptide = shortest amino-acid chain; receptor = ALL other chains (supports
    # 1- OR 2-chain receptors from co-fold). Receptor chains are merged into one
    # psfgen segment; the artificial inter-receptor-chain bond appears identically
    # in E_complex and E_receptor so it CANCELS in dG = Ecom - Erec - Elig.
    st = gemmi.read_structure(cif); st.setup_entities(); m = st[0]
    ch = [(c.name, sum(is_aa(r) for r in c)) for c in m]
    ch = [c for c in ch if c[1] > 0]
    if len(ch) < 2:
        raise SystemExit("FATAL: complex %s has <2 amino-acid chains" % cif)
    ch.sort(key=lambda x: x[1])
    pep = ch[0][0]
    recs = set(c[0] for c in ch[1:])

    def write_chains(names, path, renumber):
        s = gemmi.Structure(); md = gemmi.Model('1'); c2 = gemmi.Chain('X')
        for c in m:
            if c.name not in names:
                continue
            for r in c:
                if is_aa(r):
                    c2.add_residue(r)
        md.add_chain(c2); s.add_model(md); s.setup_entities()
        if renumber:
            n = 0
            for r in s[0][0]:
                n += 1
                r.seqid = gemmi.SeqId(n, ' ')
        s.write_pdb(path)
        return sum(1 for _ in c2)

    npep = write_chains({pep}, tag + '_pep.pdb', True)
    nrec = write_chains(recs, tag + '_rec.pdb', False)
    return nrec, npep

HEADTAIL = '''* head-to-tail patch
*
   36  1
PRES CYCP         0.00
BOND 1C 2N

END
'''
open('headtail.top', 'w').write(HEADTAIL)
ALIASES = [('HIS', 'HSD'), ('HID', 'HSD'), ('HIE', 'HSE'), ('HIP', 'HSP')]

def build_psf(kind, tag, npep):
    g = PsfGen()
    g.read_topology(RTF); g.read_topology('headtail.top')
    for a, b in ALIASES:
        try:
            g.alias_residue(top_resname=b, pdb_resname=a)
        except Exception:
            try:
                g.alias_residue(a, b)
            except Exception:
                pass
    try:
        g.alias_atom(resname='ILE', top_atomname='CD', pdb_atomname='CD1')
    except Exception:
        try:
            g.alias_atom('ILE', 'CD', 'CD1')
        except Exception:
            pass
    if kind in ('complex', 'receptor'):
        g.add_segment(segid='REC', pdbfile=tag + '_rec.pdb')
        g.read_coords(segid='REC', filename=tag + '_rec.pdb')
    if kind in ('complex', 'ligand'):
        g.add_segment(segid='PEP', pdbfile=tag + '_pep.pdb', first='none', last='none')
        g.read_coords(segid='PEP', filename=tag + '_pep.pdb')
        g.patch('CYCP', [('PEP', str(npep)), ('PEP', '1')])
    g.regenerate_angles(); g.regenerate_dihedrals()
    try:
        g.guess_coords()
    except Exception:
        pass
    psf = tag + '_' + kind + '.psf'; pdb = tag + '_' + kind + '.pdb'
    g.write_psf(filename=psf); g.write_pdb(filename=pdb)
    return psf, pdb

params_set = app.CharmmParameterSet(RTF, PRM)

def make_system(psf):
    p = app.CharmmPsfFile(psf)
    sysm = p.createSystem(params_set, nonbondedMethod=app.CutoffNonPeriodic,
                          nonbondedCutoff=2.0 * unit.nanometer,
                          constraints=app.HBonds, implicitSolvent=app.GBn2)
    return p, sysm

def energy(system, positions):
    integ = mm.VerletIntegrator(1.0 * unit.femtoseconds)
    ctx = mm.Context(system, integ, CPU)
    ctx.setPositions(positions)
    e = ctx.getState(getEnergy=True).getPotentialEnergy().value_in_unit(unit.kilocalorie_per_mole)
    del ctx, integ
    return e

def ring_closed(lp):
    # head-to-tail test: a bond between N of residue 1 and C of the last residue
    # (Pro-safe, unlike a raw bond count which proline side-chain rings inflate).
    def idx(res, nm):
        for a in res.atoms:
            if a.name == nm:
                return a.idx
        return None
    ni = idx(lp.residues[0], 'N'); ci = idx(lp.residues[-1], 'C')
    if ni is None or ci is None:
        return False
    return bool(any({b.atom1.idx, b.atom2.idx} == {ni, ci} for b in lp.bonds))

tag = PEP_ID.replace('/', '_')
rec = {'peptide_id': PEP_ID, 'complex_cif': os.path.basename(CIF)}
try:
    nrec, npep = split_complex(CIF, tag)
    rec['nrec_res'] = nrec; rec['npep_res'] = npep
    cpsf, cpdb = build_psf('complex', tag, npep)
    rpsf, _ = build_psf('receptor', tag, npep)
    lpsf, _ = build_psf('ligand', tag, npep)

    lp = pmd.load_file(lpsf)
    rec['ligand_ring_closed'] = ring_closed(lp)
    def _olc(r):
        t = gemmi.find_tabulated_residue(r.name)
        return (t.one_letter_code.upper() if t else 'X')
    rec['seq'] = ''.join(_olc(r) for r in lp.residues)

    # minimize complex, then single-point MM-GBSA
    cp, csys = make_system(cpsf)
    pos = app.PDBFile(cpdb).getPositions()
    integ = mm.LangevinMiddleIntegrator(300 * unit.kelvin, 1 / unit.picosecond,
                                        0.002 * unit.picoseconds)
    sim = app.Simulation(cp.topology, csys, integ, PLAT)
    sim.context.setPositions(pos)
    sim.minimizeEnergy(maxIterations=5000)

    rp, rsys = make_system(rpsf)
    lp2, lsys = make_system(lpsf)
    natom_rec = rsys.getNumParticles()
    st = sim.context.getState(getPositions=True); P = st.getPositions()
    Ecom = energy(csys, P)
    Erec = energy(rsys, P[:natom_rec])
    Elig = energy(lsys, P[natom_rec:])
    rec['dG_bind_kcal_mol'] = round(float(Ecom - Erec - Elig), 2)
    rec['E_complex_kcal'] = round(Ecom, 1)
    rec['E_receptor_kcal'] = round(Erec, 1)
    rec['E_ligand_kcal'] = round(Elig, 1)
    rec['protocol'] = 'minimized single-point, implicit GBn2 (CHARMM36m), CPU'
    rec['ok'] = True
    print("%s: dG = %s kcal/mol (ring_closed=%s, %s-mer)" % (
        tag, rec['dG_bind_kcal_mol'], rec['ligand_ring_closed'], rec['npep_res']))
except Exception as e:
    import traceback
    rec['ok'] = False
    rec['error'] = type(e).__name__ + ': ' + str(e)[:200]
    traceback.print_exc()

rec['note'] = ('RELATIVE within-target MM-GBSA ranking (Sun PCCP 2019), not '
               'absolute affinity; entropy omitted; cyclic via psfgen CYCP '
               'patch. Trust only ring_closed=true rows.')
with open("%s_mmgbsa.json" % PEP_ID.replace('/', '_'), "w") as f:
    json.dump(rec, f, indent=2)
print(json.dumps(rec, indent=2))

if not rec.get('ok'):
    raise SystemExit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        openmm: \$(python3 -c "import openmm; print(openmm.__version__)" 2>/dev/null || echo unknown)
        python: \$(python3 --version | cut -d' ' -f2)
    END_VERSIONS
    """
}

workflow PEPTIDE_MMGBSA {
    take:
    ch_complexes   // channel: tuple(pep_id, path(complex_cif)) — ONE per complex → parallel

    main:
    MMGBSA(ch_complexes)

    emit:
    results  = MMGBSA.out.results
    versions = MMGBSA.out.versions
}

// Entry workflow for standalone execution.
workflow {
    // FAN OUT: each complex CIF matched by params.complexes becomes its own
    // channel emission → its own MMGBSA task → AWS Batch runs them in parallel.
    ch_complexes = Channel
        .fromPath(params.complexes, checkIfExists: true)
        .map { f -> tuple(f.baseName, f) }

    PEPTIDE_MMGBSA(ch_complexes)

    PEPTIDE_MMGBSA.out.results.view { pid, f -> "mmgbsa done: ${pid}" }
}
