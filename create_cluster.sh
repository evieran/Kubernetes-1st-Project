#!/usr/bin/env bash
#vi: set ft=bash:

# This script will provision a cluster with the Terraform configuration provided.
# 
# **NOTE**: This was _not_ reviewed during the course and is provided as-is with
# no additional support.
#
# To learn more about Terraform, visit https://terraform.io.
REBUILD="${REBUILD:-false}"
REINSTALL_AWS_LBIC="${REINSTALL_AWS_LBIC:-false}"
TERRAFORM_DOCKER_IMAGE="terraform-awscli:latest"
AWS_DOCKER_IMAGE="amazon/aws-cli:2.2.9"
EKSCTL_DOCKER_IMAGE="weaveworks/eksctl:0.60.0"
HELM_DOCKER_IMAGE="alpine/k8s:1.21.2"
AWS_LBIC_VERSION="2.2.0"
AWS_LBIC_POLICY_URL="https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v$AWS_LBIC_VERSION/docs/install/iam_policy.json"

terraform() {
  docker run --rm -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-""}" \
    -e "AWS_REGION=$AWS_REGION" \
    -e "TF_IN_AUTOMATION=true" \
    -v "$HOME/.kube:/root/.kube" \
    -v "$PWD:/work" -w /work "$TERRAFORM_DOCKER_IMAGE" "$@"
}

aws() {
  docker run --rm -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-""}" \
    -e "AWS_REGION=$AWS_REGION" \
    -v "$PWD:/work" \
    -v "$HOME/.kube/config:/root/.kube/config" \
    -v "/tmp:/tmp" \
    -w /work \
    "$AWS_DOCKER_IMAGE" "$@"
}

eksctl() {
  docker run --rm -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-""}" \
    -e "AWS_REGION=$AWS_REGION" \
    -v "$PWD:/work" \
    -v "$HOME/.kube/config:/root/.kube/config" \
    -v "/tmp:/tmp" \
    -w /work \
    --entrypoint eksctl \
    "$EKSCTL_DOCKER_IMAGE" "$@"
}

helm() {
  docker run --rm -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-""}" \
    -e "AWS_REGION=$AWS_REGION" \
    -e "TF_IN_AUTOMATION=true" \
    -v "$PWD:/work" \
    -v "$HOME/.kube:/root/.kube" \
    -v "$HOME/.helm:/root/.helm" \
    -v "$HOME/.config/helm:/root/.config/helm" \
    -v "$HOME/.cache/helm:/root/.cache/helm" \
    -w /work \
    "$HELM_DOCKER_IMAGE" helm "$@"
}

kubectl() {
  docker run --rm -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-""}" \
    -e "AWS_REGION=$AWS_REGION" \
    -e "TF_IN_AUTOMATION=true" \
    -v "$PWD:/work" \
    -v "$HOME/.kube:/root/.kube" \
    -v "$HOME/.helm:/root/.helm" \
    -v "$HOME/.config/helm:/root/.config/helm" \
    -v "$HOME/.cache/helm:/root/.cache/helm" \
    -w /work \
    "$HELM_DOCKER_IMAGE" kubectl "$@"
}

set_eks_context() {
  aws eks update-kubeconfig --name explore-california-cluster
}

state_bucket_exists() {
  2>/dev/null aws s3 ls "$TERRAFORM_S3_BUCKET"
}

initialize_terraform() {
  docker build -f "$(dirname "$0")/terraform.Dockerfile" -t "$TERRAFORM_DOCKER_IMAGE" . && \
  &>/dev/null pushd "$INFRA_PATH"
  terraform init \
    -backend-config="bucket=$TERRAFORM_S3_BUCKET" \
    -backend-config="key=$TERRAFORM_S3_KEY"
}

create_cluster() {
  terraform apply -auto-approve
}

install_alb_ingress_controller() {
  _create_or_get_policy() {
    policy=$(aws iam list-policies |
      jq -r '.Policies[] | select(.PolicyName == "explore-california-awslbic-policy") | .Arn')
    if ! test -z "$policy"
    then
      echo "$policy"
      return 0
    fi
    json=$(curl "$AWS_LBIC_POLICY_URL")
    aws iam create-policy --policy-name explore-california-awslbic-policy \
      --policy-document "$json" | jq -r .Arn
  }

  _create_service_account() {
    eksctl create iamserviceaccount \
      --cluster="explore-california-cluster" \
      --namespace=kube-system \
      --name=aws-load-balancer-controller \
      --attach-policy-arn="$1" \
      --override-existing-serviceaccounts \
      --approve && \
    kubectl create serviceaccount aws-load-balancer-controller
  }

  _install_crds() {
    kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
  }

  _install_awslbic() {
    helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
      --set clusterName="explore-california-cluster" \
      --set serviceAccount.create=false \
      --set serviceAccount.name=aws-load-balancer-controller \
      -n kube-system
  }

  _create_oidc_provider() {
    eksctl utils associate-iam-oidc-provider \
      --region=us-east-2 \
      --cluster=explore-california-cluster \
      --approve
  }

  _create_oidc_provider &&
  policy_arn=$(_create_or_get_policy)
  _create_service_account "$policy_arn" &&
    _install_crds &&
    _install_awslbic
}

eks_cluster_exists() {
  grep -Eiq '^false$' <<< "$REBUILD" && ( aws eks list-clusters | grep -q "explore-california-cluster" )
}

aws_lbic_installed() {
  grep -Eiq '^false$' <<< "$REINSTALL_AWS_LBIC" && ( helm list -n kube-system | grep -q "aws-load-balancer-controller" )
}

install_aws_spot_termination_handler() {
  helm install stable/k8s-spot-termination-handler --namespace kube-system || true
}

install_vpc_cni() {
  _create_or_get_aws_node_sa() {
    post_creation="${1:-false}"
    role=$(eksctl get iamserviceaccount --cluster="explore-california-cluster" \
      --namespace="kube-system" -o json | \
      jq -r '.[] | select(.metadata.name == "aws-node") | .status.roleARN')
    if ! test -z "$role"
    then
      echo "$role"
      return 0
    elif test "$post_creation" == "true"
    then
      return 1
    fi
    eksctl create iamserviceaccount \
        --name aws-node \
        --namespace kube-system \
        --cluster "explore-california-cluster" \
        --attach-policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
        --approve \
        --override-existing-serviceaccounts
    _create_or_get_aws_node_sa "true"
  }
  if ! helm list | grep -q "aws-vpc-cni"
  then
   service_account_role=$(_create_or_get_aws_node_sa)
   eksctl create addon \
      --name vpc-cni \
      --version latest \
      --cluster "explore-california-cluster" \
      --service-account-role-arn "$service_account_role" \
      --force
  fi
}

cleanup() {
  test "$PWD" == "$INFRA_PATH" && &>/dev/null popd
}

set -euo pipefail
trap 'cleanup' SIGINT SIGHUP EXIT

INFRA_PATH="$(dirname "$0")/infra"
TERRAFORM_S3_BUCKET="${TERRAFORM_S3_BUCKET?Please provide an S3 bucket to store state into.}"
TERRAFORM_S3_KEY="${TERRAFORM_S3_KEY?Please provide the key to use for state}"

if eks_cluster_exists
then
  >&2 echo "INFO: EKS cluster already exists. Run this with REBUILD_CLUSTER=true to rebuild."
  set_eks_context
else
  if ! state_bucket_exists
  then
    >&2 echo "ERROR: S3 bucket does not exist: $TERRAFORM_S3_BUCKET/$TERRAFORM_S3_KEY"
    exit 1
  fi
  initialize_terraform && create_cluster && set_eks_context && install_aws_spot_termination_handler
fi

if aws_lbic_installed
then
  >&2 echo "INFO: AWS LBIC installed. Run this with REINSTALL_AWS_LBIC=true to re-install."
else
  install_alb_ingress_controller
fi

install_vpc_cni
