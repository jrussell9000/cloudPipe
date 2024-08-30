
import importlib
import subprocess
import sys

# try:
#     import yaml
# except ImportError:
#     subprocess.call([sys.executable, "-m", "pip", "install", "pyyaml"])
#     import yaml
    
# with open('/install/fastsurfer.yml', 'r') as f:
#     y = yaml.safe_load(f)
#     y['dependencies'][-1]['pip'].extend(['keyring==25.2.1','keyrings.alt==5.0.1','nda-tools==0.2.27','sqlalchemy==2.0.31','boto3==1.34.130','oracledb==2.2.1'])

# with open('/install/fastsurfer.yml', 'w') as fo:
#     fo.write(yaml.dump(y, default_flow_style=False, sort_keys=False))

subprocess.call(["pip", "install", "--prefix", "/venv", 'keyring==25.2.1','keyrings.alt==5.0.1',
                 'nda-tools==0.3.0','sqlalchemy==2.0.31','boto3==1.34.130','oracledb==2.2.1'])
