#!/bin/sh

customer_managed_policy_arns=`aws iam list-policies --scope Local --query 'Policies[*].Arn' --output text`
for arn in $customer_managed_policy_arns; do
    aws iam delete-policy --policy-arn "$arn"
done

