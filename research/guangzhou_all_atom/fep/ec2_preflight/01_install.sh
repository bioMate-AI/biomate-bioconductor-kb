#!/bin/bash
exec > /tmp/install2.log 2>&1
set -x
echo "START $(date)"
export PATH=/opt/conda/bin:$PATH
# conda-forge only (avoids defaults/main ToS); includes a C compiler + git for pmx build
conda install -y --override-channels -c conda-forge \
  "gromacs=2024.*" parmed gemmi openmm numpy scipy git pip c-compiler
echo "=== gmx ==="; /opt/conda/bin/gmx --version 2>/dev/null | grep -i "GROMACS version" || echo GMX_MISSING
# pmx (deGrootLab) — the FEP hybrid tool. Try conda-forge, else build from GitHub.
conda install -y --override-channels -c conda-forge pmx 2>/dev/null && echo PMX_CONDA_OK || {
  /opt/conda/bin/pip install "git+https://github.com/deGrootLab/pmx.git" 2>&1 | tail -4 ; }
echo "=== pmx check ==="
/opt/conda/bin/python -c "import pmx, os; print('PMX_OK', os.path.dirname(pmx.__file__))" 2>&1 | tail -1
/opt/conda/bin/python -c "from pmx import ligand_alchemy" 2>&1 | tail -1 || true
command -v pmx && pmx --help 2>&1 | head -3 || echo "pmx CLI: $(ls /opt/conda/bin/pmx* 2>/dev/null)"
/opt/conda/bin/python -c "import parmed,gemmi,openmm; print('parmed+gemmi+openmm OK')" 2>&1 | tail -1
echo "DONE $(date)"
