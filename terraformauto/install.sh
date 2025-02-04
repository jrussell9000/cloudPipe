#!/bin/bash

export AWS_DEFAULT_REGION="us-east-2"

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
  "module.ebs_csi_driver_irsa"
  "module.eks_blueprints_addons"
  "module.karpenter"
)

# Initialize Terraform
terraform init -upgrade

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$(terraform apply -target="$target" -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$(terraform apply -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi

aws eks update-kubeconfig --name cloudpipe --region $AWS_DEFAULT_REGION
