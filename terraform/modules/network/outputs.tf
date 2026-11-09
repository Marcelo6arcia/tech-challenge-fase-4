output "vpc_id" {
  value       = aws_vpc.this.id
  description = "ID da VPC"
}

output "vpc_cidr" {
  value       = aws_vpc.this.cidr_block
  description = "CIDR da VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "IDs das subnets públicas"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "IDs das subnets privadas"
}

output "availability_zones" {
  value       = local.azs
  description = "AZs utilizadas"
}
