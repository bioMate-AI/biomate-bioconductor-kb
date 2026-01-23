#!/bin/bash -ue
python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import design_primer

# Run the tool
try:
    result = design_primer(
    sequence="ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG",
    start_pos=10,
    primer_length=20,
    min_gc=0.4,
    max_gc=0.6,
    min_tm=55.0,
    max_tm=65.0,
    search_window=100
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("design_primer_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("design_primer_output.txt", "w") as f:
    f.write("Biomni: Design Primer Results
")
    f.write("=" * 60 + "

")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}
")
    else:
        f.write(str(result))

print("design_primer completed successfully")
PYEOF
