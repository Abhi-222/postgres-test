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
  ssh_public_key = file("~/.ssh/id_ed25519.pub") 
} 

# Access module outputs at the root level
output "app_bastion_ip" {
  value = module.production_postgres.bastion_public_ip
}

