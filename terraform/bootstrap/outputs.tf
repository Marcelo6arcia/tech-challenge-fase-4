output "state_bucket_name" {
  value       = aws_s3_bucket.tfstate.id
  description = "Nome do bucket S3 — copie para terraform/envs/dev/backend.hcl"
}

output "backend_config_snippet" {
  description = "Conteúdo pronto para o arquivo terraform/envs/dev/backend.hcl"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.tfstate.id}"
    key          = "togglemaster/dev/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
