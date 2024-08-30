import boto3
import json
import pandas as pd

client = boto3.client('batch')

csvIn = pd.read_csv("subject_timepoints.csv")
subj_time_list = csvIn['subject_timepoint'].tolist()

for subject_timepoint in subj_time_list[0:1]:
    segjob_response = client.submit_job(
        jobName="-".join([subject_timepoint, "seg"]),
        # If the revision tag (e.g, :4) isn't specified, AWS automagically grabs the latest version
        jobDefinition='arn:aws:batch:us-east-1:026415314835:job-definition/fast-batch-job-def-seg',
        jobQueue='arn:aws:batch:us-east-1:026415314835:job-queue/fastbatch_job_queue_gpu',
        eksPropertiesOverride={
            'podProperties': {
                'containers': [{
                    'env': [{
                        'name': 'BATCHSIZE',
                        'value': subject_timepoint
                    }],
                }]
            }
        }
    )   
    segjob_id = segjob_response['jobId']
 
    # surfjob_response = client.submit_job(
    #     jobName="-".join([subject_timepoint, "surf"]),
    #     jobDefinition='arn:aws:batch:us-east-1:026415314835:job-definition/fast-batch-job-def-surf',
    #     jobQueue='arn:aws:batch:us-east-1:026415314835:job-queue/fastbatch_job_queue_cpu',
    #     eksPropertiesOverride = {
    #         'podProperties': {
    #             'containers': [{
    #                 'env': [{
    #                     'name': 'SUBJECTTIMEPOINT',
    #                     'value': subject_timepoint
    #                 }],
    #             }]
    #         }
    #     },
    #     dependsOn=[{
    #             'jobId': segjob_id,
    #     }]
    # )

    # print(f'Submitted FastSurfer job for subject-timepoint {subject_timepoint} to AWS Batch job queue.')