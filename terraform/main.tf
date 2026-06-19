# ====================================================================
# ADDING THIS BLOCK TO THE VERY TOP OF YOUR ROOT main.tf FILE
# ====================================================================
variable "ssh_public_key" {
  type        = string
  description = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK8uF0jlBO8sAT4bgFH1jieZST+7aXk8Z5E863xWkZhL sa>
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

