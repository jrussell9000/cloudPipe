import json
import tarfile
import urllib.parse
from io import BytesIO
import boto3
import os
import logging
from botocore.exceptions import ClientError
from botocore.config import Config
from boto3.s3.transfer import TransferConfig
import rapidgzip
import resource

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configure S3 client with retry configuration
s3 = boto3.client('s3', 
    config=Config(
        retries = dict(
            max_attempts = 10,
            mode = 'adaptive'
        )
    )
)

def process_task(task):
    """Process a single S3 Batch Operation task"""

    try:
        bucket = task['s3BucketArn'].split(':')[-1]
        key = urllib.parse.unquote_plus(task['s3Key'])
        
        if not key.endswith('.tgz'):
            raise ValueError(f"Input file {key} is not a .tgz file")
            
        # Process the file
        extract_and_upload(bucket, key)
        
        return {
            'taskId': task['taskId'],
            'resultCode': 'Succeeded',
            'resultString': f'Successfully processed {key}'
        }
        
    except Exception as e:
        logger.error(f"Error processing {key}: {str(e)}")
        return {
            'taskId': task['taskId'],
            'resultCode': 'PermanentFailure',
            'resultString': str(e)
        }

def extract_and_upload(bucket, tgz_key, chunk_size=8388608):  # 8MB chunks
    """Extract and upload files using streaming to minimize memory usage"""
    
    gz_stream = None
    tar = None
    # Configure multipart upload
    transfer_config = TransferConfig(
        multipart_threshold=chunk_size,
        multipart_chunksize=chunk_size,
        max_concurrency=10,
        use_threads=True
    )

    # Stream the compressed file
    try:
        # Get object size first
        response = s3.head_object(Bucket=bucket, Key=tgz_key)
        file_size = response['ContentLength']
        
        # Use range requests for large files
        if file_size > 100 * 1024 * 1024:  # 100MB
            position = 0
            buffer = BytesIO()
            
            while position < file_size:
                end = min(position + chunk_size - 1, file_size - 1)
                range_header = f'bytes={position}-{end}'
                
                chunk = s3.get_object(
                    Bucket=bucket,
                    Key=tgz_key,
                    Range=range_header
                )['Body'].read()
                
                buffer.write(chunk)
                position = end + 1
                
            buffer.seek(0)
            tgz_data = buffer
            
        else:
            # For smaller files, read all at once
            response = s3.get_object(Bucket=bucket, Key=tgz_key)
            tgz_data = BytesIO(response['Body'].read())

        # Use rapidgzip for parallel decompression
        with rapidgzip.open(tgz_data, parallelization=os.cpu_count()) as gz_stream:
            with tarfile.open(fileobj=gz_stream, mode='r') as tar:
                while True:
                    try:
                        member = tar.next()
                        if member is None:
                            break
                        # Skip if not a file
                        elif member.isfile():
                            # Stream each file from tar to S3
                            file_obj = tar.extractfile(member)
                            if file_obj is None:
                                continue
                                
                            # Determine output key - strip any leading slashes
                            output_key = member.name.lstrip('/')

                            s3.upload_fileobj(
                                Fileobj=file_obj,
                                Bucket=bucket,
                                Key=output_key,
                                Config=transfer_config,
                                ExtraArgs={
                                    'ContentType': guess_content_type(output_key)
                                }
                            )
                            logger.info(f"Uploaded {output_key}")
                        elif member.isdir():
                            s3.put_object(Bucket=bucket, Key=member.name + '/')
                        else:
                            logger.info(f"Skipping {member.name}")
                            continue
                    except ClientError as e:
                        logger.error(f"Error uploading {output_key}: {str(e)}")
                        raise

    except Exception as e:
        logger.error(f"Extraction error for {tgz_key}: {str(e)}")
        raise

    finally:
        if tar:
            tar.close()
        if gz_stream:
            gz_stream.close()

def guess_content_type(filename):
    """Guess the content type based on file extension"""
    import mimetypes
    content_type, _ = mimetypes.guess_type(filename)
    return content_type or 'application/octet-stream'

def lambda_handler(event, context):
    """Main Lambda handler for S3 Batch operations"""
    
    # set_resource_limits()
    # Validate input
    if 'tasks' not in event:
        raise ValueError("Invalid S3 Batch event format")
    
    results = []
    for task in event['tasks']:
        result = process_task(task)
        results.append(result)
    
    return {
        'invocationSchemaVersion': event['invocationSchemaVersion'],
        'treatMissingKeysAs': 'PermanentFailure',
        'invocationId': event['invocationId'],
        'results': results
    }
