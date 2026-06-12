data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for TerraFusion EC2 (Jenkins + k3s)"
  vpc_id      = aws_vpc.main.id
  tags = { Name = "${var.project_name}-ec2-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = var.ssh_allowed_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP — Frontend"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = var.ssh_allowed_cidr
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  description       = "Jenkins UI"
}

resource "aws_vpc_security_group_ingress_rule" "kube_api" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = var.ssh_allowed_cidr
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  description       = "k3s Kubernetes API"
}

resource "aws_vpc_security_group_ingress_rule" "nodeport_range" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = var.ssh_allowed_cidr
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
  description       = "K8s NodePort range"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_pair_name

  user_data = replace(
    replace(
      file("${path.module}/../scripts/server-init.sh"),
      "__REPLACE_ME__",    aws_db_instance.mysql.address
    ),
    "__RDS_PASSWORD__",    aws_db_instance.mysql.password
  )

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
    tags = { Name = "${var.project_name}-root-volume" }
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.project_name}-server" }
}

resource "aws_eip" "main" {
  domain   = "vpc"
  instance = aws_instance.main.id
  tags     = { Name = "${var.project_name}-eip" }
}
