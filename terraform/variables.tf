variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (EC2)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (RDS)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m7i-flex.large"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_db_name" {
  description = "RDS database name"
  type        = string
  default     = "terrafusion"
}

variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "terrafusion_admin"
}

variable "rds_master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "ssh_allowed_cidr" {
  description = "Your IP CIDR for SSH + Jenkins + K8s API access"
  type        = string
}

variable "public_key_path" {
  description = "Absolute path to your SSH public key"
  type        = string
}

variable "aws_access_key_id" {
  description = "AWS access key ID for EC2 (your existing IAM user)"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key for EC2 (your existing IAM user)"
  type        = string
  sensitive   = true
}

variable "git_repo_url" {
  description = "Git repository URL for the app"
  type        = string
  default     = "https://github.com/YOUR_ORG/terrafusion-platform.git"
}

variable "deploy_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}

variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "terrafusion"
}
