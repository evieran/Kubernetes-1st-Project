terraform {
  backend "s3" {}
}

data "aws_eks_cluster" "cluster" {
  name = module.explore-california-cluster.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.explore-california-cluster.cluster_id
}

data "aws_availability_zones" "available" {
  state = "available"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  config_path            = "~/.kube/config"
}

resource "aws_security_group" "enable_ssh" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.explore-california-vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/16"
    ]
  }
}

module "explore-california-vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "explore-california"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 1, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  // These tags are required in order for the AWS ALB ingress controller to
  // detect the subnets from which your targets will be pulled.
  // https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
  private_subnet_tags = {
    "kubernetes.io/cluster/explore-california-cluster": "owned",
    "kubernetes.io/role/elb": "1"
  }
  public_subnet_tags = {
    "kubernetes.io/cluster/explore-california-cluster": "owned",
    "kubernetes.io/role/elb": "1"
  }

  // The VPC needs to have access to the Internet and be able to assign DNS
  // hostnames to EC2/adjacent instances within it for EKS workers to join your
  // cluster (which isn't an EC2 instance set that you manage)
  enable_nat_gateway = true
  enable_vpn_gateway = true
  enable_dns_support = true
  enable_dns_hostnames = true
}

module "explore-california-cluster" {
  source          = "./module"
  cluster_name    = "explore-california-cluster"
  cluster_version = "1.20"
  subnets          = module.explore-california-vpc.public_subnets
  vpc_id          = module.explore-california-vpc.vpc_id
  worker_groups = [
    {
      instance_type = "t3.medium"
      asg_max_size  = 5
      spot_price = "0.02"
      additional_security_group_ids = [ aws_security_group.enable_ssh.id ]
      kubelet_extra_args = "--node-labels=node.kubernetes.io/lifecycle=spot"
      suspended_processes = ["AZRebalance"]
    },
    {
      instance_type = "t3.large"
      asg_max_size  = 5
      spot_price = "0.03"
      additional_security_group_ids = [ aws_security_group.enable_ssh.id ]
      kubelet_extra_args = "--node-labels=node.kubernetes.io/lifecycle=spot"
      suspended_processes = ["AZRebalance"]
    }
  ]
}

resource "aws_ecr_repository" "explore-california" {
  name = "explore-california"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
