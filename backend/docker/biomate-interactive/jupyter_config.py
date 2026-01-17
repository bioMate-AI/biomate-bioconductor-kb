# Jupyter configuration for BioMate Interactive
import os

c = get_config()

c.ServerApp.ip = '127.0.0.1'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.allow_origin = '*'
c.ServerApp.allow_remote_access = True
c.ServerApp.disable_check_xsrf = True
c.ServerApp.base_url = '/jupyter'
c.ServerApp.trust_xheaders = True
c.ServerApp.root_dir = '/home/rstudio'
c.ServerApp.notebook_dir = '/home/rstudio'
