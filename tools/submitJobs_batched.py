import boto3
from boto3.dynamodb.conditions import Attr
import os
import sys

# setting path
sys.path.append(f'{os.path.dirname(os.path.realpath(__file__))}/..')
from batched import config

session = boto3.Session(
    aws_access_key_id=config.aws_access_key_id,
    aws_secret_access_key=config.aws_secret_access_key,
    region_name=config.aws_region
)

dynamodb = session.resource('dynamodb')
batch = session.client('batch')
dbtable = dynamodb.Table(config.trackingdb_tablename)

def getBatchIndex(dbtable, all: bool = False):
    if all:
        indexScan = dbtable.scan(
            ConsistentRead=True,
            ProjectionExpression='BatchIndex'
        )
        # Need to convert these to integers to sort the list
        rawBatchIndex = [int(d['BatchIndex']) for d in indexScan['Items']]
        while 'LastEvaluatedKey' in indexScan:
            indexScan = dbtable.scan(
                ConsistentRead=True,
                ProjectionExpression='BatchIndex',
                ExclusiveStartKey=indexScan['LastEvaluatedKey']
            )
            rawBatchIndex.extend([int(d['BatchIndex']) for d in indexScan['Items']])

    else:
        indexScan = dbtable.scan(
            FilterExpression=Attr('InProcessing').eq(0) & Attr('Segmented').eq(0),
            ConsistentRead=True,
            ProjectionExpression='BatchIndex'
        )
        rawBatchIndex = [int(d['BatchIndex']) for d in indexScan['Items']]
        while 'LastEvaluatedKey' in indexScan:
            indexScan = dbtable.scan(
                FilterExpression=Attr('InProcessing').eq(0) & Attr('Segmented').eq(0),
                ConsistentRead=True,
                ProjectionExpression='BatchIndex',
                ExclusiveStartKey=indexScan['LastEvaluatedKey']
            )
            rawBatchIndex.extend([int(d['BatchIndex']) for d in indexScan['Items']])

    batchIndex = list(dict.fromkeys(rawBatchIndex))
    batchIndex.sort()
    # AWS Batch environment variables must be strings
    batchIndex = [str(r) for r in batchIndex]
    return batchIndex


def submitJob(batchIndexValue):
    # Env variable values MUST be strngs
    segjob_response = batch.submit_job(
        jobName="-".join(["fastsegmentation", batchIndexValue]),
        # If the revision tag (e.g, :4) isn't specified, AWS automagically grabs the latest version
        jobDefinition='arn:aws:batch:us-east-1:026415314835:job-definition/fast-batch-job-def-seg',
        jobQueue='arn:aws:batch:us-east-1:026415314835:job-queue/fastbatch_job_queue_gpu',
        eksPropertiesOverride={
            'podProperties': {
                'containers': [{
                    'env': [{
                        'name': 'BATCHINDEX',
                        'value': batchIndexValue
                    }],
                }],
            }
        }
    )

    print(segjob_response)


batchIndex = getBatchIndex(dbtable, False)

for indexValue in batchIndex[0:101]:
    submitJob(indexValue)
