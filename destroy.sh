#!/bin/bash
set -e

echo "Initialising teardown..."

# 1. Get Cluster Details from Terraform
echo "Fetching cluster details from Terraform..."
REGION=$(terraform output -raw region)
CLUSTER_NAME=$(terraform output -raw cluster_name)

if [ -z "$REGION" ] || [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Could not fetch region or cluster_name from terraform output."
  echo "Make sure terraform init and plan have been run (or state exists)."
  exit 1
fi

echo "Cluster: $CLUSTER_NAME in $REGION"

# 2. Update kubeconfig to ensure we can talk to the cluster
echo "Updating kubeconfig..."
aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME"

# 3. Delete External Resources (LoadBalancers, Ingresses, PVCs with EBS)
echo "Cleaning up Kubernetes resources that create AWS dependencies..."

# Delete all Services of type LoadBalancer in all namespaces
echo "Deleting LoadBalancer Services..."
kubectl get svc --all-namespaces -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.namespace + " " + .metadata.name' | while read namespace name; do
  echo "Deleting svc/$name in namespace $namespace"
  kubectl delete svc "$name" -n "$namespace" --timeout=30s || true
done

# Delete all Ingresses in all namespaces
echo "Deleting Ingress resources..."
kubectl delete ingress --all --all-namespaces --timeout=30s || true

# Optional: Delete PVCs if you are using dynamic provisioning for EBS volumes
# echo "Deleting PVCs..."
# kubectl delete pvc --all --all-namespaces --timeout=30s || true

echo "Waiting 30 seconds for AWS resources (ALBs, NLBs) to be cleaned up by Cloud Controllers..."
sleep 30

# 4. Run Terraform Destroy
echo "Running terraform destroy..."
terraform destroy -auto-approve
