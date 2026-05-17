# =============================================================================
# Pre-destroy cleanup — removes resources created by the AWS Load Balancer
# Controller that Terraform does not manage (ELBs, k8s-elb-* security groups,
# orphaned ENIs). Without this, terraform destroy fails with DependencyViolation
# on the VPC because those resources still reference the VPC subnets/IGW.
# =============================================================================
resource "null_resource" "vpc_pre_destroy_cleanup" {
  triggers = {
    vpc_cidr     = var.vpc_cidr
    cluster_name = var.cluster_name
    region       = var.region
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set +e
      REGION="${self.triggers.region}"
      CLUSTER="${self.triggers.cluster_name}"

      echo "[pre-destroy] Finding VPC by cluster tag..."
      VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
        --filters "Name=tag:Name,Values=$CLUSTER-*-vpc" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

      if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        echo "[pre-destroy] No VPC found, skipping cleanup."
        exit 0
      fi

      echo "[pre-destroy] VPC: $VPC_ID — cleaning up LB-controller resources..."

      # Delete classic ELBs
      for lb in $(aws elb describe-load-balancers --region "$REGION" \
        --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" \
        --output text 2>/dev/null); do
        echo "[pre-destroy] Deleting ELB: $lb"
        aws elb delete-load-balancer --region "$REGION" --load-balancer-name "$lb" || true
      done

      # Delete ALBs / NLBs
      for arn in $(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null); do
        echo "[pre-destroy] Deleting ALB/NLB: $arn"
        aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn" || true
      done

      sleep 25

      # Delete orphaned k8s-managed security groups
      for sg in $(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[?starts_with(GroupName,'k8s-elb-') || starts_with(GroupName,'k8s-sg-')].GroupId" \
        --output text 2>/dev/null); do
        echo "[pre-destroy] Deleting SG: $sg"
        aws ec2 delete-security-group --region "$REGION" --group-id "$sg" || true
      done

      # Clean up orphaned ENIs
      for eni in $(aws ec2 describe-network-interfaces --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null); do
        ATTACH_ID=$(aws ec2 describe-network-interfaces --region "$REGION" \
          --network-interface-ids "$eni" \
          --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
          --output text 2>/dev/null || echo "None")
        if [ "$ATTACH_ID" != "None" ] && [ -n "$ATTACH_ID" ]; then
          aws ec2 detach-network-interface --region "$REGION" \
            --attachment-id "$ATTACH_ID" --force || true
          sleep 3
        fi
        aws ec2 delete-network-interface --region "$REGION" \
          --network-interface-id "$eni" || true
      done

      echo "[pre-destroy] Cleanup complete."
    EOT
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-${count.index + 1}"

    # Required by AWS Load Balancer Controller for internet-facing ALBs
    "kubernetes.io/role/elb" = "1"

    # Required for Kubernetes/EKS ownership and discovery alignment
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-${var.environment}-public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-eks-cluster-sg"
  description = "Security group for the PetClinic EKS control plane"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Allow all outbound traffic from EKS control plane"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-eks-cluster-sg"
  }
}

resource "aws_security_group" "eks_node" {
  name        = "${var.cluster_name}-eks-node-sg"
  description = "Security group attached to PetClinic EKS worker nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow all traffic from EKS control plane security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [
      aws_security_group.eks_cluster.id
    ]
  }

  ingress {
    description = "Allow inter-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Allow kubelet API from EKS control plane"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    security_groups = [
      aws_security_group.eks_cluster.id
    ]
  }

  egress {
    description = "Allow all outbound traffic from worker nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-eks-node-sg"
  }
}

resource "aws_security_group_rule" "eks_cluster_ingress_from_nodes_https" {
  description              = "Allow EKS worker nodes to reach the EKS API server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_node.id
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "Security group for PetClinic RDS MySQL"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow MySQL only from EKS worker nodes"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [
      aws_security_group.eks_node.id
    ]
  }

  egress {
    description = "Allow outbound traffic from RDS security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-rds-sg"
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "Security group for public Application Load Balancer"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow public HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow public HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Forward traffic to EKS nodes on NodePort range"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_node.id]
  }

  egress {
    description     = "Forward traffic to API gateway pod on port 8080"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_node.id]
  }

  tags = {
    Name = "${var.project}-${var.environment}-alb-sg"
  }
}
