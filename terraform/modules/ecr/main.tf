# =============================================================================
# MÓDULO: ecr
# Um repositório por microsserviço.
# =============================================================================
#
# image_tag_mutability = IMMUTABLE é deliberado: no GitOps a tag da imagem é o
# identificador do artefato promovido (v1.0.0-<sha>). Se a tag pudesse ser
# sobrescrita, o commit no repositório GitOps deixaria de descrever com precisão
# o que está rodando no cluster — o oposto de "se não está no código, não existe".
# =============================================================================

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Name = each.value })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expira imagens sem tag apos 1 dia"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Mantem apenas as ${var.keep_last_images} imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
