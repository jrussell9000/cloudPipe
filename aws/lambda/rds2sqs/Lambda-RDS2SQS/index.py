import boto3
import sys
import logging
import pymysql
import json
import os

from botocore.exceptions import ClientError

headers = {"X-Aws-Parameters-Secrets-Token": os.environ.get('AWS_SESSION_TOKEN')}

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# rds settings
rds_host = 'proxy-1737652459064-brave-abcd-dbinstance.proxy-c9quuwwes0p8.us-east-2.rds.amazonaws.com'
name = 'admin'
db_name = 'brave_abcd_db'

secret_name = "rds!db-8407abb4-859c-4606-bd24-a212b9cbe660"
my_session = boto3.session.Session()
region_name = "us-east-2"
conn = None

# Get the service resource.
lambdaClient = boto3.client('lambda')


def openConnection():
    print("In Open connection")
    global conn
    password = "None"
    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    
    # In this sample we only handle the specific exceptions for the 'GetSecretValue' API.
    # See https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
    # We rethrow the exception by default.
    
    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
        print(get_secret_value_response)
    except ClientError as e:
        print(e)
        if e.response['Error']['Code'] == 'DecryptionFailureException':
            # Secrets Manager can't decrypt the protected secret text using the provided KMS key.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InternalServiceErrorException':
            # An error occurred on the server side.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            # You provided an invalid value for a parameter.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            # You provided a parameter value that is not valid for the current state of the resource.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'ResourceNotFoundException':
            # We can't find the resource that you asked for.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
    else:
        # Decrypts secret using the associated KMS CMK.
        # Depending on whether the secret is a string or binary, one of these fields will be populated.
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            j = json.loads(secret)
            password = j['password']
        else:
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            print("password binary:" + decoded_binary_secret)
            password = decoded_binary_secret.password    
    
    try:
        if(conn is None):
            conn = pymysql.connect(
                rds_host, user=name, passwd=password, db=db_name, connect_timeout=5)
        elif (not conn.open):
            # print(conn.open)
            conn = pymysql.connect(
                rds_host, user=name, passwd=password, db=db_name, connect_timeout=5)

    except Exception as e:
        print (e)
        print("ERROR: Unexpected error: Could not connect to MySql instance.")
        raise e



def lambda_handler(event, context):

    item_count = 0
    try:
        openConnection()
        with conn.cursor() as cur:
            cur.execute("select * from BIDSID")
            body = cur.fetchall()
            for row in body:
                print(row)
                item_count += 1
                print(item_count)  
    except Exception as e:
        print(e)
    finally:
        print("Closing connection")
        if(conn is not None and conn.open):
            conn.close()
        
        # """
    # This function fetches content from MySQL RDS instance
    # """
    # QUEUE_URL = 'https://sqs.us-east-2.amazonaws.com/575108944090/cloudpipe-jobqueue.fifo'
    # sqs = boto3.client('sqs')
    # queue_url = os.environ['QUEUE_URL']
    # with conn.cursor() as cur:
    #     cur.execute("select * from BIDSID")
    #     body = cur.fetchall()
    #     for row in body:
    #         # response = sqs.send_message(
    #         #     QueueUrl=queue_url,
    #         #     DelaySeconds=10,
    #         #     MessageBody=json.dumps(row)
    #         # )
    #         print(response['MessageId'])