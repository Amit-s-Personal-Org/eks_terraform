#!/bin/bash
set -e

echo "Initialising creation..."

# 1. Run Terraform Apply
echo "Applying Terraform configuration..."
terraform init
terraform apply -auto-approve

# 2. Get Cluster Details from Terraform
echo "Fetching cluster details from Terraform..."
REGION=$(terraform output -raw region)
CLUSTER_NAME=$(terraform output -raw cluster_name)

if [ -z "$REGION" ] || [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Could not fetch region or cluster_name from terraform output."
  exit 1
fi

echo "Cluster: $CLUSTER_NAME in $REGION"

# 3. Update kubeconfig to ensure we can talk to the cluster
echo "Updating kubeconfig..."
aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME"

echo "Success! Cluster is ready and kubectl is configured."
kubectl get nodes
