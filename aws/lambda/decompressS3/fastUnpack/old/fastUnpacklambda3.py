import tarfile
import urllib.parse
from io import BytesIO
from mimetypes import guess_type
import boto3
from boto3.s3.transfer import TransferConfig
import os

import rapidgzip

# s3 = boto3.client('s3')
# GB = 1024 ** 3
# config = TransferConfig(multipart_threshold=0.2 * GB, max_concurrency=200)

# dest_bucket_name = 'test041125'
from memory_profiler import profile

@profile
def lambda_handler(event):

    s3 = boto3.client('s3')

    config = boto3.s3.transfer.TransferConfig(
        multipart_threshold=8 * 1024 * 1024,
        multipart_chunksize=8 * 1024 * 1024
    )
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    tgz_key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
    tar_key = tgz_key.replace('.tgz', '.tar')
    response = s3.get_object(Bucket=bucket_name, Key=tgz_key)
    tgz_data = BytesIO(response['Body'].read())
    with rapidgzip.open(tgz_data, parallelization=os.cpu_count()) as gz_stream:
        with tarfile.open(fileobj=gz_stream, mode='r') as tar:
            for filename in tar.getnames():
                s3.upload_fileobj(
                    Fileobj=tar.extractfile(filename),
                    Bucket=bucket_name,
                    Key=filename,
                    Config=config
                )


event = {
    "Records": [
        {
            "eventVersion": "2.1",
            "eventSource": "aws:s3",
            "awsRegion": "us-east-2",
            "eventTime": "2019-09-03T19:37:27.192Z",
            "eventName": "ObjectCreated:Copy",
            "userIdentity": {
                "principalId": "575108944090"
            },
            "requestParameters": {
                "sourceIPAddress": "205.255.255.255"
            },
            "responseElements": {
                "x-amz-request-id": "D82B88E5F771F645",
                "x-amz-id-2": "vlR7PnpV2Ce81l0PRw6jlUpck7Jo5ZsQjryTjKlc5aLWGVHPZLj5NeC6qMa0emYBDXOo6QBU0Wo="
            },
            "s3": {
                "s3SchemaVersion": "1.0",
                "configurationId": "828aa6fc-f7b5-4305-8584-487c791949c1",
                "bucket": {
                    "name": "abcd-mri",
                    "ownerIdentity": {
                        "principalId": "575108944090"
                    },
                    "arn": "arn:aws:s3:::abcd-mri"
                },
                "object": {
                    "key": "NDARINV003RTV85_baselineYear1Arm1_ABCD-MPROC-SST-fMRI_20181001105213.tgz",
                    "size": 522200000,
                    "eTag": "22683c2c027a76d43aa1439e5b7ac783",
                    "sequencer": "0C0F6F405D6ED209E1"
                }
            }
        }
    ]
}

lambda_handler(event)
