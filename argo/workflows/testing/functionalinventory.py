from pathlib import Path, PurePosixPath
import json
import os
import time

try:
    import boto3
except ImportError:
    os.system('python -m pip -q --disable-pip-version-check install --root-user-action=ignore boto3')
    import boto3


s3 = boto3.client('s3')
sessions = []
response = s3.list_objects_v2(
    Bucket='abcd-working',
    Prefix='inputs/sub-NDARINV0PANNNLF/ses-baselineYear1Arm1/func/',
    Delimiter='/')
tasks = []
for o in response.get('Contents'):
    prefix = PurePosixPath(o.get('Key'))
    if prefix.suffix == ".nii":
        filename = prefix.name
        task = filename.split('_')[2].replace('task-', '').replace('.nii', '')
        if task not in tasks:
            tasks.append(task)
print(tasks)
