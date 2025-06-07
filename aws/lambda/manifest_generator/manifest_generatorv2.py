import boto3
import csv
import json
import argparse
import os
from datetime import datetime
from botocore.config import Config
from typing import List, Dict, Optional
from tqdm import tqdm
import sys

class ManifestGenerator:
    def __init__(self, source_bucket: str, prefix: Optional[str] = None):
        """
        Initialize the manifest generator.

        Args:
            source_bucket (str): The source S3 bucket name
            prefix (str, optional): Prefix to filter objects in the bucket
        """
        self.source_bucket = source_bucket
        self.prefix = prefix

        # Configure S3 client with retry strategy
        self.s3_client = boto3.client('s3', config=Config(
            retries={'max_attempts': 3, 'mode': 'adaptive'},
            max_pool_connections=50
        ))

    def _get_total_objects(self) -> int:
        """Get total number of objects in bucket/prefix for progress bar"""
        try:
            paginator = self.s3_client.get_paginator('list_objects_v2')
            total = 0

            for page in paginator.paginate(
                Bucket=self.source_bucket,
                Prefix=self.prefix if self.prefix else ''
            ):
                if 'Contents' in page:
                    total += len(page['Contents'])

            return total
        except Exception as e:
            print(f"Warning: Could not get total object count: {str(e)}")
            return 0

    def _get_objects(self,
                     min_size: Optional[int] = None,
                     max_size: Optional[int] = None,
                     file_extension: Optional[str] = None) -> List[Dict]:
        """
        Get objects from S3 bucket with optional filtering and progress bar.

        Args:
            min_size (int, optional): Minimum file size in bytes
            max_size (int, optional): Maximum file size in bytes
            file_extension (str, optional): File extension to filter (e.g., '.txt')

        Returns:
            List[Dict]: List of S3 objects matching the criteria
        """
        objects = []
        total_objects = self._get_total_objects()

        try:
            paginator = self.s3_client.get_paginator('list_objects_v2')
            page_iterator = paginator.paginate(
                Bucket=self.source_bucket,
                Prefix=self.prefix if self.prefix else ''
            )

            # Initialize progress bar for object listing
            with tqdm(total=total_objects,
                      desc="Listing objects",
                      unit="obj",
                      bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]") as pbar:

                for page in page_iterator:
                    if 'Contents' not in page:
                        continue

                    for obj in page['Contents']:
                        # Apply filters
                        if min_size and obj['Size'] < min_size:
                            pbar.update(1)
                            continue
                        if max_size and obj['Size'] > max_size:
                            pbar.update(1)
                            continue
                        if file_extension and not obj['Key'].endswith(file_extension):
                            pbar.update(1)
                            continue

                        objects.append({
                            'Bucket': self.source_bucket,
                            'Key': obj['Key'],
                            'Size': obj['Size'],
                            'LastModified': obj['LastModified'].isoformat()
                        })
                        pbar.update(1)

        except Exception as e:
            raise Exception(f"Error listing objects in bucket {self.source_bucket}: {str(e)}")

        return objects

    def generate_csv_manifest(self,
                              output_file: str,
                              min_size: Optional[int] = None,
                              max_size: Optional[int] = None,
                              file_extension: Optional[str] = None,
                              include_version: bool = False) -> str:
        """
        Generate a CSV manifest file for S3 Batch Operations with progress bar.
        """
        objects = self._get_objects(min_size, max_size, file_extension)

        if not objects:
            raise Exception("No objects found matching the specified criteria")

        try:
            with open(output_file, 'w', newline='') as csvfile:
                headers = ['Bucket', 'Key']
                if include_version:
                    headers.append('VersionId')

                writer = csv.DictWriter(csvfile,
                                        fieldnames=headers,
                                        quoting=csv.QUOTE_ALL)
                writer.writeheader()

                # Initialize progress bar for writing manifest
                with tqdm(total=len(objects),
                          desc="Writing CSV manifest",
                          unit="obj",
                          bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]") as pbar:

                    for obj in objects:
                        row = {
                            'Bucket': obj['Bucket'],
                            'Key': obj['Key']
                        }
                        if include_version:
                            row['VersionId'] = ''
                        writer.writerow(row)
                        pbar.update(1)

            return output_file

        except Exception as e:
            raise Exception(f"Error writing manifest file: {str(e)}")

    # This doesn't work. The output JSON manifest lacks necessary header information (e.g., checksum) and is
    # therefore rejected by S3 Batch Ops. Took too long to figure this out. Could fix it, but it's easier
    # to just use CSV files instead.
    # def generate_json_manifest(self,
    #                            output_file: str,
    #                            min_size: Optional[int] = None,
    #                            max_size: Optional[int] = None,
    #                            file_extension: Optional[str] = None,
    #                            extra_args: Optional[Dict] = None) -> str:
    #     """
    #     Generate a JSON manifest file for S3 Batch Operations with progress bar.
    #     """
    #     objects = self._get_objects(min_size, max_size, file_extension)

    #     if not objects:
    #         raise Exception("No objects found matching the specified criteria")

    #     try:
    #         with open(output_file, 'w') as jsonfile:
    #             # Initialize progress bar for writing manifest
    #             with tqdm(total=len(objects),
    #                       desc="Writing JSON manifest",
    #                       unit="obj",
    #                       bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]") as pbar:

    #                 for obj in objects:
    #                     manifest_entry = {
    #                         'bucket': obj['Bucket'],
    #                         'key': obj['Key']
    #                     }

    #                     if extra_args:
    #                         manifest_entry.update(extra_args)

    #                     jsonfile.write(json.dumps(manifest_entry) + '\n')
    #                     pbar.update(1)

    #         return output_file

    #     except Exception as e:
    #         raise Exception(f"Error writing manifest file: {str(e)}")

    def upload_manifest(self,
                        manifest_file: str,
                        manifest_bucket: str,
                        manifest_prefix: Optional[str] = None) -> Dict:
        """
        Upload the manifest file to S3 with progress bar.
        """
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            file_name = manifest_file.split('/')[-1]
            manifest_key = f"{manifest_prefix}/{timestamp}_{file_name}" if manifest_prefix else f"{timestamp}_{file_name}"

            # Get file size for progress bar
            file_size = os.path.getsize(manifest_file)

            # Create progress bar callback
            with tqdm(total=file_size,
                      desc="Uploading manifest",
                      unit='B',
                      unit_scale=True,
                      unit_divisor=1024,
                      bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]") as pbar:

                def callback(bytes_transferred):
                    pbar.update(bytes_transferred)

                self.s3_client.upload_file(
                    manifest_file,
                    manifest_bucket,
                    manifest_key,
                    Callback=callback
                )

            return {
                'bucket': manifest_bucket,
                'key': manifest_key,
                'etag': self.s3_client.head_object(
                    Bucket=manifest_bucket,
                    Key=manifest_key
                )['ETag']
            }

        except Exception as e:
            raise Exception(f"Error uploading manifest to S3: {str(e)}")

def format_size(size):
    """Format size in bytes to human readable format"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024.0:
            return f"{size:.1f} {unit}"
        size /= 1024.0

def main():
    parser = argparse.ArgumentParser(description='Generate S3 Batch Operations manifest file')
    parser.add_argument('--source-bucket', required=True, help='Source S3 bucket')
    parser.add_argument('--prefix', help='Optional prefix filter')
    parser.add_argument('--output', required=True, help='Output file path')
    parser.add_argument('--format', choices=['csv', 'json'], default='csv', help='Manifest format')
    parser.add_argument('--min-size', type=int, help='Minimum file size in bytes')
    parser.add_argument('--max-size', type=int, help='Maximum file size in bytes')
    parser.add_argument('--extension', help='File extension filter')
    parser.add_argument('--manifest-bucket', help='S3 bucket to upload manifest')
    parser.add_argument('--manifest-prefix', help='S3 prefix for manifest')

    args = parser.parse_args()

    try:
        print(f"\nInitializing manifest generation for bucket: {args.source_bucket}")
        if args.prefix:
            print(f"Prefix filter: {args.prefix}")
        if args.min_size:
            print(f"Minimum size filter: {format_size(args.min_size)}")
        if args.max_size:
            print(f"Maximum size filter: {format_size(args.max_size)}")
        if args.extension:
            print(f"File extension filter: {args.extension}")
        print("\n")

        generator = ManifestGenerator(args.source_bucket, args.prefix)

        # if args.format == 'csv':
        manifest_file = generator.generate_csv_manifest(
            args.output,
            args.min_size,
            args.max_size,
            args.extension
        )
        # else:
        #     manifest_file = generator.generate_json_manifest(
        #         args.output,
        #         args.min_size,
        #         args.max_size,
        #         args.extension
        #     )

        print(f"\nGenerated manifest file: {manifest_file}")

        if args.manifest_bucket:
            manifest_info = generator.upload_manifest(
                manifest_file,
                args.manifest_bucket,
                args.manifest_prefix
            )
            print(f"Uploaded manifest to S3: s3://{manifest_info['bucket']}/{manifest_info['key']}")

    except Exception as e:
        print(f"\nError: {str(e)}", file=sys.stderr)
        exit(1)


if __name__ == "__main__":
    main()
