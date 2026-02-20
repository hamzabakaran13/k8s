# Security Group za control-plane nodes
resource "aws_security_group" "cp" {
  name   = "${var.name}-cp-sg"
  vpc_id = aws_vpc.this.id

  # Kubernetes API (6443) - dolazi preko public NLB-a, pa source može biti tvoj IP.
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_api_cidr]
  }

  # etcd peer/client
  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # kubelet API
  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # controller-manager, scheduler (secure ports)
  ingress {
    description = "kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Lab-friendly: allow all traffic within VPC (pod-to-pod / node-to-node kasnije)
  ingress {
    description = "All traffic within VPC (lab)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-cp-sg" }
}

# Security Group za worker nodes
resource "aws_security_group" "wk" {
  name   = "${var.name}-wk-sg"
  vpc_id = aws_vpc.this.id

  # kubelet
  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NodePort range (lab)
  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Lab-friendly: allow all within VPC
  ingress {
    description = "All traffic within VPC (lab)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-wk-sg" }
}

# (Opcionalno) SG za VPC endpoints (ako enable_vpc_endpoints=true)
resource "aws_security_group" "vpce" {
  count  = var.enable_vpc_endpoints ? 1 : 0
  name   = "${var.name}-vpce-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-vpce-sg" }
}
