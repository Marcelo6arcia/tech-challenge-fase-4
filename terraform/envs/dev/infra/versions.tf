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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # -------------------------------------------------------------------------
  # BACKEND REMOTO — requisito explícito da Fase 3
  # -------------------------------------------------------------------------
  # A configuração é parcial de propósito: o nome do bucket sai do módulo
  # bootstrap e é injetado no init, de modo que nada específico da conta fique
  # hardcoded no repositório.
  #
  #   terraform init -backend-config=backend.hcl
  #
  # use_lockfile = true habilita o lock nativo do S3 (Terraform >= 1.10),
  # dispensando a tabela DynamoDB usada historicamente para esse fim.
  # -------------------------------------------------------------------------
  backend "s3" {}
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = local.common_tags
  }
}
