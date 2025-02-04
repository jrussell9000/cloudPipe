import base64
import boto3
import json
import pymysql
from botocore.exceptions import ClientError


# rds settings
rds_host = 'brave-abcd-dbinstance.c9quuwwes0p8.us-east-2.rds.amazonaws.com'
name = 'admin'
db_name = 'brave_abcd_db'
region_name = "us-east-2"
secret_name = "rds!db-8407abb4-859c-4606-bd24-a212b9cbe660"
conn = None

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
        if (conn is None):
            conn = pymysql.connect(
                host=rds_host, user=name, passwd=password, db=db_name, connect_timeout=5)
        elif (not conn.open):
            # print(conn.open)
            conn = pymysql.connect(
                host=rds_host, user=name, passwd=password, db=db_name, connect_timeout=5)

    except Exception as e:
        print(e)
        print("ERROR: Unexpected error: Could not connect to MySql instance.")
        raise e

    return conn

def fillqueue():
    """
    This function fetches content from mysql RDS instance
    """
    conn = openConnection()

    with conn.cursor() as cur:
        # cur.execute("insert into brave_abcd_db.brave_abcd_table (name) values('TestName')")
        # conn.commit()
        cur.execute("select BIDSID from brave_abcd_db.ABCDsubjs2db")
        output = cur.fetchall()

    sqs = boto3.client('sqs')
    queue_url = sqs.get_queue_url(QueueName='cloudpipe-jobqueue.fifo')['QueueUrl']
    id_list_length = len(output)
    mod_10 = id_list_length % 10
    iter_list = [*range(0, id_list_length - mod_10, 10), *range(id_list_length - mod_10, id_list_length + 1)]
    for i in iter_list:
        queue_entries = []
        for j in range(10):
            if i + j < id_list_length:
                print(output[i + j][0])
        #         queue_entries.append({'Id': output[i + j][0], 'MessageBody': output[i + j][0], 'MessageGroupId': 'ABCDsubjeseIDs'})
        # sqs.send_message_batch(QueueUrl=queue_url, Entries=queue_entries)

    return "Added %d items from RDS to SQS" % (len(output))


fillqueue()
