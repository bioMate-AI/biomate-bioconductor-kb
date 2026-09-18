#!/usr/bin/env python3
"""Launch the real Galaxy backend with only trial-local state and inference."""
import os,secrets
import xml.etree.ElementTree as ET
from pathlib import Path
root=Path('/opt/biomate-trial'); app=root/'app/backend'; state=root/'galaxy-state'
for name in ['', 'files','tmp','tool-data','jobs']:(state/name).mkdir(parents=True,exist_ok=True)
(app/'database').mkdir(exist_ok=True)
knowledge=app/'database/galaxy_ai_tools.db'
if not knowledge.exists():knowledge.symlink_to(root/'knowledge/galaxy_ai_tools.db')
sample=app/'lib/galaxy/config/sample'
bootstrap_key=state/'bootstrap-admin.key'
if not bootstrap_key.exists():
    fd=os.open(bootstrap_key,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as keyfile:keyfile.write(secrets.token_hex(32))
tool_config=state/'tool_conf.xml'
tree=ET.ElementTree(ET.Element('toolbox',{'monitor':'false'}))
# Trial installation exposes only the locally provisioned, exercised tools.
# Galaxy's sample catalogue includes external data-source initialization.
ET.SubElement(tree.getroot(),'tool',{'file':str(app/'tools/data_source/upload.xml')})
ET.SubElement(tree.getroot(),'tool',{'file':str(root/'scripts/fastqc.xml')})
tree.write(tool_config,encoding='unicode')
config=state/'galaxy.yml'
config.write_text('galaxy:\n'+''.join(f'  {k}: {v}\n' for k,v in {
'root':str(app),'database_connection':'sqlite:///'+str(state/'universe.sqlite')+'?isolation_level=IMMEDIATE',
'install_database_connection':'sqlite:///'+str(state/'install.sqlite'),
'database_auto_migrate':'true','file_path':str(state/'files'),'new_file_path':str(state/'tmp'),
'data_dir':str(state),'tool_data_path':str(state/'tool-data'),
'job_working_directory':str(state/'jobs'),'tool_config_file':str(tool_config),
'datatypes_config_file':str(sample/'datatypes_conf.xml.sample'),'enable_ai_assistant':'true',
'watch_tools':'false','watch_tool_data':'false','watch_job_rules':'false',
'bootstrap_admin_api_key':bootstrap_key.read_text().strip(),'smtp_server':'null'}.items()))
config.chmod(0o600)
env={'PATH':str(root/'app-venv/bin')+':/usr/local/bin:/usr/bin:/bin','HOME':str(root/'app-home'),
'PYTHONPATH':str(app/'lib'),'GALAXY_CONFIG_FILE':str(config),'GALAXY_CONFIG_ENABLE_AI_ASSISTANT':'true',
'BIOMATE_KNOWLEDGE_DB':str(knowledge),'BIOMATE_LOCAL_ONLY':'1','BIOMATE_LOCAL_LLM_URL':'http://127.0.0.1:8000/v1',
'BIOMATE_LOCAL_LLM_ORIGIN':'http://127.0.0.1:8000','BIOMATE_LOCAL_LLM_MODEL':'Qwen/Qwen3.8-27B',
'BIOMATE_LOCAL_LLM_TIMEOUT_MS':'600000','NEXTFLOW_USE_AWS':'false','BILLING_DEV_MODE':'true',
'JAVA_BILLING_ENABLED':'false','AWS_EC2_METADATA_DISABLED':'true','AWS_SHARED_CREDENTIALS_FILE':'/dev/null','AWS_CONFIG_FILE':'/dev/null'}
os.chdir(app)
os.execve(str(root/'app-venv/bin/python'),['python','-m','uvicorn','--factory','galaxy.webapps.galaxy.fast_factory:factory','--host','127.0.0.1','--port','8082'],env)
