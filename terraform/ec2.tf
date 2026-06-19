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
  description       = "HTTP - Frontend"
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

  # EC2 and RDS created in parallel (~9 min saved). server-init.sh uses
  # ${RDS_HOST:-__REPLACE_ME__} / ${RDS_PASSWORD:-__RDS_PASSWORD__} fallbacks.
  user_data = file("${path.module}/../scripts/server-init.sh")

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

# After EC2 + RDS are both created, push real RDS values into the EC2's
# k8s ConfigMap and .env file. This is needed because user_data runs
# before RDS is available (parallel provisioning) and uses placeholders.
resource "null_resource" "rds_config" {
  depends_on = [aws_instance.main, aws_db_instance.mysql, aws_eip.main]

  provisioner "local-exec" {
    command = <<-EOCMD
      for i in $(seq 1 60); do
        ssh -o StrictHostKeyChecking=no -i ~/${var.key_pair_name}.pem ubuntu@${aws_eip.main.public_ip} \
          'echo connected' 2>/dev/null && break
        sleep 10
      done
      ssh -o StrictHostKeyChecking=no -i ~/${var.key_pair_name}.pem ubuntu@${aws_eip.main.public_ip} \
        'kubectl create configmap backend-config -n terrafusion \
          --from-literal=DB_HOST=${aws_db_instance.mysql.address} \
          --from-literal=DB_PORT=${aws_db_instance.mysql.port} \
          --from-literal=DB_NAME=${aws_db_instance.mysql.db_name} \
          --from-literal=DB_USER=${aws_db_instance.mysql.username} \
          --from-literal=DB_TYPE=mysql \
          --from-literal=NODE_ENV=production \
          --dry-run=client -o yaml | kubectl apply -f - && \
         kubectl create secret generic backend-secret -n terrafusion \
          --from-literal=DB_PASSWORD=${var.rds_master_password} \
          --from-literal=JWT_SECRET=terrafusion-38cc941eeb6cad3f21ac7f9508f489c0 \
          --dry-run=client -o yaml | kubectl apply -f - && \
         kubectl delete pod -n terrafusion -l app=backend && \
         sudo sed -i "s|__REPLACE_ME__|${aws_db_instance.mysql.address}|g" /opt/terrafusion/backend/.env && \
         sudo sed -i "s|__RDS_PASSWORD__|${var.rds_master_password}|g" /opt/terrafusion/backend/.env'
    EOCMD
  }
}
