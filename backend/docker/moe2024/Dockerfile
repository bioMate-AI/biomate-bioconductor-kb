# MOE 2024 Placeholder
# MOE (Molecular Operating Environment) requires a Chemical Computing Group commercial license.
# Replace this image with your licensed MOE 2024 container before running moe_covalent_docking.
FROM python:3.11-slim
RUN echo '#!/usr/bin/env python3\nimport sys\nprint("ERROR: MOE 2024 commercial license required.")\nprint("This workflow uses MOE covalent docking (Chemical Computing Group).")\nprint("Provide a licensed moe2024:latest image to run this workflow.")\nsys.exit(1)' > /usr/local/bin/moe_check.py
ENTRYPOINT ["python3", "/usr/local/bin/moe_check.py"]
