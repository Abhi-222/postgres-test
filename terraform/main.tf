# ====================================================================
# ADDING THIS BLOCK TO THE VERY TOP OF YOUR ROOT main.tf FILE
# ====================================================================
variable "ssh_public_key" {
  type        = string
  description = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK8uF0jlBO8sAT4bgFH1jieZST+7aXk8Z5E863xWkZhL sahil@sahil"
}

# Provider configuration follows right after
provider "aws" {
  region = "us-east-2"
}

module "production_postgres" {
  source = "./modules/postgres_ha"

  # Overwriting defaults dynamically
  environment   = "production"
  instance_type = "t3.small"
  vpc_cidr      = "10.50.0.0/16"

  # This MUST be inside the module block braces
  ssh_public_key = var.ssh_public_key 
} 

# Access module outputs at the root level
output "app_bastion_ip" {
  value = module.production_postgres.bastion_public_ip
}

# ====================================================================
# THE BRIDGE OUTPUT: Passes the IP from the module up to Jenkins
# ====================================================================
output "bastion_public_ip" {
  value       = module.production_postgres.bastion_public_ip
  description = "Exposes the child module bastion IP directly to the Jenkins runner"
}

output "master_private_ip" {
  value       = aws_instance.postgres_master.private_ip
  description = "The private IP address of the primary database cluster"
}

output "replica_1_private_ip" {
  value       = aws_instance.postgres_replica_1.private_ip
}

output "replica_2_private_ip" {
  value       = aws_instance.postgres_replica_2.private_ip
}
