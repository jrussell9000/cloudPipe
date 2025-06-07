import boto3
import os
import json
import subprocess
import tempfile
from typing import Dict
from botocore.config import Config

class S3Compressor:
    def __init__(self):
        # Configure S3 client with retry strategy
        self.s3 = boto3.client('s3', config=Config(
            retries={'max_attempts': 3, 'mode': 'adaptive'},
            max_pool_connections=50
        ))
        self.tmp_dir = tempfile.mkdtemp()

    def _download_file(self, bucket: str, key: str, local_path: str) -> bool:
        """Download a single file from S3"""
        try:
            self.s3.download_file(bucket, key, local_path)
            return True
        except Exception as e:
            print(f"Error downloading {key}: {str(e)}")
            return False

    def _compress_file(self, input_path: str) -> str:
        """Compress a file using pigz"""
        try:
            # Use pigz with 2 threads (Lambda has 2 vCPUs) and fastest compression
            process = subprocess.run(
                ['pigz', '-1', '-p2', '-f', input_path],
                capture_output=True,
                text=True,
                check=True
            )
            return f"{input_path}.gz"
        except subprocess.CalledProcessError as e:
            print(f"Compression error: {e.stderr}")
            raise
        except Exception as e:
            print(f"Unexpected error during compression: {str(e)}")
            raise

    def _upload_file(self, local_path: str, bucket: str, key: str) -> bool:
        """Upload a compressed file to S3"""
        try:
            self.s3.upload_file(local_path, bucket, key)
            return True
        except Exception as e:
            print(f"Error uploading {key}: {str(e)}")
            return False

    def process_file(self, source_bucket: str, source_key: str,
                     dest_bucket: str, dest_key: str) -> Dict:
        """Process a single file for S3 Batch Operations"""
        result = {
            'key': source_key,
            'success': False,
            'error': None
        }

        try:
            # Only process .nii files that aren't already compressed
            if not source_key.endswith('.nii') or source_key.endswith('.nii.gz'):
                return {
                    'resultCode': 'Succeeded',
                    'resultString': 'File is not a .nii file or is already compressed'
                }

            # Create temporary file paths
            input_path = os.path.join(self.tmp_dir, os.path.basename(source_key))

            # Download
            if not self._download_file(source_bucket, source_key, input_path):
                return {
                    'resultCode': 'PermanentFailure',
                    'resultString': 'Failed to download source file'
                }

            try:
                # Compress
                compressed_path = self._compress_file(input_path)

                # Upload compressed file
                compressed_key = f"{os.path.splitext(dest_key)[0]}.nii.gz"
                if not self._upload_file(compressed_path, dest_bucket, compressed_key):
                    return {
                        'resultCode': 'PermanentFailure',
                        'resultString': 'Failed to upload compressed file'
                    }

                return {
                    'resultCode': 'Succeeded',
                    'resultString': f'Successfully compressed and uploaded to {compressed_key}'
                }

            finally:
                # Cleanup temporary files
                for temp_file in [input_path, f"{input_path}.gz"]:
                    try:
                        if os.path.exists(temp_file):
                            os.remove(temp_file)
                    except Exception as e:
                        print(f"Warning: Could not delete temporary file {temp_file}: {str(e)}")

        except Exception as e:
            return {
                'resultCode': 'PermanentFailure',
                'resultString': f'Error processing file: {str(e)}'
            }

def lambda_handler(event, context):
    """AWS Lambda handler for S3 Batch Operations"""
    try:
        # Parse the S3 Batch Operations event
        invocation_schema_version = event['invocationSchemaVersion']
        invocation_id = event['invocationId']
        task = event['tasks'][0]
        task_id = task['taskId']

        # Get source object information
        s3_key = task['s3Key']
        s3_bucket = task['s3BucketArn'].split(':')[-1]

        # Get destination configuration from environment variables
        dest_bucket = os.environ.get('DESTINATION_BUCKET', s3_bucket)
        dest_prefix = os.environ.get('DESTINATION_PREFIX', '')

        # Calculate destination key
        dest_key = os.path.join(dest_prefix, s3_key) if dest_prefix else s3_key

        # Process the file
        compressor = S3Compressor()
        result = compressor.process_file(s3_bucket, s3_key, dest_bucket, dest_key)

        # Return the result in S3 Batch Operations format
        return {
            'invocationSchemaVersion': invocation_schema_version,
            'treatMissingKeysAs': 'PermanentFailure',
            'invocationId': invocation_id,
            'results': [{
                'taskId': task_id,
                **result
            }]
        }

    except Exception as e:
        # Handle any unexpected errors
        return {
            'invocationSchemaVersion': invocation_schema_version,
            'treatMissingKeysAs': 'PermanentFailure',
            'invocationId': invocation_id,
            'results': [{
                'taskId': task_id,
                'resultCode': 'PermanentFailure',
                'resultString': f"Unexpected error: {str(e)}"
            }]
        }
