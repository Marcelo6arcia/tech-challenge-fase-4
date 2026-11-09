variable "repository_names" {
  description = "Nomes dos repositórios ECR"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "IMMUTABLE ou MUTABLE"
  type        = string
  default     = "IMMUTABLE"
}

variable "keep_last_images" {
  description = "Quantidade de imagens mantidas por repositório"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Permite destruir o repositório mesmo com imagens dentro"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags aplicadas aos recursos"
  type        = map(string)
  default     = {}
}
