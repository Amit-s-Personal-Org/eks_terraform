# PowerShell script to create EKS cluster using Terraform
# Exit on error
$ErrorActionPreference = "Stop"

Write-Host "Initialising creation..."

# 1. Run Terraform Apply
Write-Host "Applying Terraform configuration..."
terraform init
terraform apply -auto-approve

# 2. Get Cluster Details from Terraform
Write-Host "Fetching cluster details from Terraform..."
$REGION = (terraform output -raw region)
$CLUSTER_NAME = (terraform output -raw cluster_name)

if ([string]::IsNullOrEmpty($REGION) -or [string]::IsNullOrEmpty($CLUSTER_NAME)) {
  Write-Host "Error: Could not fetch region or cluster_name from terraform output."
  exit 1
}

Write-Host "Cluster: $CLUSTER_NAME in $REGION"

# 3. Update kubeconfig to ensure we can talk to the cluster
Write-Host "Updating kubeconfig..."
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME

Write-Host "Success! Cluster is ready and kubectl is configured."
kubectl get nodes
