# =============================================================================
# MÓDULO: dynamodb
# Tabela de eventos de avaliação de flags consumida pelo analytics-service.
# =============================================================================

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = "event_id"
  range_key    = "timestamp"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "flag_name"
    type = "S"
  }

  # Consulta "quantas avaliações a flag X teve no período Y"
  #
  # key_schema no lugar de hash_key/range_key: os dois estão marcados como
  # deprecated dentro de global_secondary_index a partir do provider 6.x, e um
  # aviso repetido a cada plan é ruído que a equipe aprende a ignorar.
  global_secondary_index {
    name            = "flag_name-timestamp-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "flag_name"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "timestamp"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.deletion_protection

  tags = merge(var.tags, {
    Name    = var.table_name
    Service = "analytics-service"
  })
}
