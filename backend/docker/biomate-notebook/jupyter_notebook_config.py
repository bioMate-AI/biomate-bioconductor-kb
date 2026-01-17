# Jupyter Notebook Configuration for BioMate

c = get_config()

# Allow access from any origin (for Galaxy integration)
c.NotebookApp.allow_origin = '*'
c.NotebookApp.allow_remote_access = True

# Disable token authentication (Galaxy handles auth)
c.NotebookApp.token = ''
c.NotebookApp.password = ''

# Trust notebooks in templates directory
c.NotebookApp.trust_xheaders = True

# Working directory
c.NotebookApp.notebook_dir = '/home/jovyan'

# Allow root (for Docker)
c.NotebookApp.allow_root = True

# Increase timeout for batch execution
c.NotebookApp.shutdown_no_activity_timeout = 3600

# Enable JupyterLab
c.NotebookApp.default_url = '/lab'

# For batch execution with papermill
c.KernelManager.shutdown_wait_time = 30
