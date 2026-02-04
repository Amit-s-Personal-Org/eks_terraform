# PowerShell script to destroy EKS cluster using Terraform
# Exit on error
$ErrorActionPreference = "Stop"

Write-Host "Initialising teardown..."

# 1. Get Cluster Details from Terraform
Write-Host "Fetching cluster details from Terraform..."
$REGION = (terraform output -raw region)
$CLUSTER_NAME = (terraform output -raw cluster_name)

if ([string]::IsNullOrEmpty($REGION) -or [string]::IsNullOrEmpty($CLUSTER_NAME)) {
  Write-Host "Error: Could not fetch region or cluster_name from terraform output."
  Write-Host "Make sure terraform init and plan have been run (or state exists)."
  exit 1
}

Write-Host "Cluster: $CLUSTER_NAME in $REGION"

# 2. Update kubeconfig to ensure we can talk to the cluster
Write-Host "Updating kubeconfig..."
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME

# 3. Delete External Resources (LoadBalancers, Ingresses, PVCs with EBS)
Write-Host "Cleaning up Kubernetes resources that create AWS dependencies..."

# Delete all Services of type LoadBalancer in all namespaces
Write-Host "Deleting LoadBalancer Services..."
$loadbalancerServices = kubectl get svc --all-namespaces -o json | ConvertFrom-Json | 
  Select-Object -ExpandProperty items | 
  Where-Object { $_.spec.type -eq "LoadBalancer" }

foreach ($svc in $loadbalancerServices) {
  $namespace = $svc.metadata.namespace
  $name = $svc.metadata.name
  Write-Host "Deleting svc/$name in namespace $namespace"
  kubectl delete svc $name -n $namespace --timeout=30s 2>$null || $true
}

# Delete all Ingresses in all namespaces
Write-Host "Deleting Ingress resources..."
kubectl delete ingress --all --all-namespaces --timeout=30s 2>$null || $true

# Delete lingering Security Groups created by AWS Load Balancer Controller
Write-Host "Checking for lingering Security Groups (k8s-elb-*)..."
$vpcId = (aws ec2 describe-vpcs --filters Name=tag:Name,Values="*-$CLUSTER_NAME-*" --query 'Vpcs[0].VpcId' --output text)

if (-not [string]::IsNullOrEmpty($vpcId)) {
  $securityGroups = (aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpcId" --query 'SecurityGroups[?starts_with(GroupName, `k8s-elb-`)].GroupId' --output text)
  
  if (-not [string]::IsNullOrEmpty($securityGroups)) {
    foreach ($sg_id in $securityGroups.Split()) {
      if (-not [string]::IsNullOrEmpty($sg_id)) {
        Write-Host "Deleting Security Group $sg_id..."
        aws ec2 delete-security-group --group-id $sg_id 2>$null || $true
      }
    }
  }
}

# Optional: Delete PVCs if you are using dynamic provisioning for EBS volumes
# Write-Host "Deleting PVCs..."
# kubectl delete pvc --all --all-namespaces --timeout=30s 2>$null || $true

Write-Host "Waiting 30 seconds for AWS resources (ALBs, NLBs) to be cleaned up by Cloud Controllers..."
