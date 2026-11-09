# =============================================================================
# BOOTSTRAP — Backend remoto do Terraform
# =============================================================================
# Este módulo é o "ovo e a galinha" do IaC: ele cria o bucket S3 que guardará o
# state de TODOS os outros módulos. Por isso, e SOMENTE por isso, ele usa state
# local (que é commitado como referência, sem segredos).
#
# Executar UMA ÚNICA VEZ, antes de qualquer coisa:
#   cd terraform/bootstrap && terraform init && terraform apply
#
# O locking é feito pelo próprio S3 (use_lockfile = true no backend do env),
# recurso nativo a partir do Terraform 1.10 — dispensa a tabela DynamoDB
# historicamente usada para lock.
# =============================================================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "ToggleMaster"
      Phase     = "3"
      ManagedBy = "Terraform"
      Module    = "bootstrap"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.state_bucket_prefix}-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = {
    Name = local.bucket_name
  }
}

# Versionamento: permite recuperar um state corrompido ou sobrescrito
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# O state contém endpoints, ARNs e (mesmo marcados como sensitive) valores
# de credenciais. Criptografia em repouso é obrigatória.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Nega qualquer requisição que não seja HTTPS
resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.tfstate.arn,
        "${aws_s3_bucket.tfstate.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# Expira versões antigas do state depois de 90 dias para não crescer sem controle
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
