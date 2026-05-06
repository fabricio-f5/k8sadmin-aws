resource "aws_security_group" "this" {
  name        = var.name
  description = "Kubernetes cluster SG (EC2 kubeadm)"
  vpc_id      = var.vpc_id

  tags = {
    Name = var.name
  }


  # ------------------------------------------------------------
  # Kubernetes API Server (master)
  # ------------------------------------------------------------
  ingress {
    description = "Kubernetes API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ------------------------------------------------------------
  # etcd (control plane) — restrito a instâncias do próprio SG
  # ------------------------------------------------------------
  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # ------------------------------------------------------------
  # kubelet API
  # ------------------------------------------------------------
  ingress {
    description = "kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ------------------------------------------------------------
  # NodePort services
  # ------------------------------------------------------------
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ------------------------------------------------------------
  # Comunicação entre nodes (ESSENCIAL)
  # ------------------------------------------------------------
  ingress {
    description = "All traffic between cluster nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # ------------------------------------------------------------
  # EGRESS (internet)
  # ------------------------------------------------------------
  egress {
    description = "All IPv4 outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "All IPv6 outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }
}