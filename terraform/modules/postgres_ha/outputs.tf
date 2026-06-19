output "bastion_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "The public IP address of the Bastion jump server"
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

