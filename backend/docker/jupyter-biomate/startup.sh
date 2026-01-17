#!/bin/bash
# Galaxy Interactive Tool startup script for Jupyter

# Galaxy passes these environment variables:
# - GALAXY_URL: Galaxy server URL
# - HISTORY_ID: Current history ID
# - API_KEY: User's API key (if configured)
# - REMOTE_HOST: Proxy host
# - GALAXY_WEB_PORT: Galaxy port

# Set up data directory symlinks if Galaxy mounted data
if [ -d "/import" ]; then
    ln -sf /import /home/jovyan/galaxy_data 2>/dev/null || true
fi

if [ -d "/galaxy/data" ]; then
    ln -sf /galaxy/data /home/jovyan/galaxy_data 2>/dev/null || true
fi

# Configure Jupyter for Galaxy proxy
mkdir -p /home/jovyan/.jupyter

cat > /home/jovyan/.jupyter/jupyter_notebook_config.py << 'EOF'
import os

c = get_config()

# Basic settings
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = int(os.environ.get('JUPYTER_PORT', 8888))
c.NotebookApp.open_browser = False
c.NotebookApp.token = ''
c.NotebookApp.password = ''
c.NotebookApp.allow_origin = '*'
c.NotebookApp.allow_remote_access = True
c.NotebookApp.disable_check_xsrf = True

# Galaxy proxy base URL
proxy_prefix = os.environ.get('PROXY_PREFIX', '')
if proxy_prefix:
    c.NotebookApp.base_url = proxy_prefix
    c.NotebookApp.trust_xheaders = True

# Working directory
c.NotebookApp.notebook_dir = '/home/jovyan'
EOF

# Start Jupyter
exec jupyter lab \
    --config=/home/jovyan/.jupyter/jupyter_notebook_config.py \
    --no-browser \
    --allow-root
