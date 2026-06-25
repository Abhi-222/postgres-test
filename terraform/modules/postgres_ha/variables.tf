variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "The deployment environment name"
}

variable "ami_id" {
  type        = string
  default     = "ami-0e5497a77ef21b5ac"
  description = "The AMI ID to use for EC2 instances"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "The size of the EC2 instances"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b", "us-east-2c"]
  description = "Target availability zones for subnets"
}

variable "ssh_public_key" {
  type        = string
  description = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK8uF0jlBO8sAT4bgFH1jieZST+7aXk8Z5E863xWkZhL sahil@sahil"
}

variable "allowed_app_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.0.0/8", "192.168.0.0/16"]
  description = "CIDR blocks allowed to connect to PostgreSQL port 5432"
}