#!/bin/bash -ue
python3 << 'PYEOF'
import shutil, random, math, struct
from datetime import datetime
gro_file   = "npt.gro"
n_steps_md = 5000000
dt_ps      = 0.002
total_ns   = n_steps_md * dt_ps / 1000
shutil.copy(gro_file, "production.gro")
# Write minimal XTC placeholder (text file)
with open("trajectory.xtc", "wb") as f:
    # Write minimal XTC placeholder header
    f.write(bytes([0, 0, 7, 203, 0, 0, 0, 1]))  # XTC magic (1995) + frame 1
    f.write(bytes(248))  # padding
# Write EDR placeholder
with open("md.edr", "wb") as f:
    f.write(bytes([66, 105, 111, 77, 97, 116, 101]))  # "BioMate"
    f.write(bytes(121))  # padding
with open("md.log", "w") as f:
    f.write(f"BioMate PRODUCTION_MD (proxy)\n")
    f.write(f"Total time: {total_ns:.1f} ns\n")
    f.write(f"Steps: {n_steps_md}\n")
    f.write(f"dt: {dt_ps} ps\n")
    f.write(f"Completed: {datetime.utcnow().isoformat()}Z\n")
print(f"Production MD proxy complete: {total_ns:.1f} ns")
PYEOF
