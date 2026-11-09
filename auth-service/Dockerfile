# =============================================================================
# Multi-stage build — serviço Go
# =============================================================================
# Endurecimentos aplicados na Fase 3:
#   - Go 1.25 (exigido por golang.org/x/crypto 0.55.0 e x/net 0.55.0)
#   - binário estático (CGO_ENABLED=0) sobre alpine enxuta
#   - flags -trimpath e -ldflags="-s -w": binário menor e sem caminhos locais
#   - processo roda como usuário sem privilégio (UID 10001)
# =============================================================================

FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git ca-certificates

# Dependências fixadas e verificadas contra os checksums versionados.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -mod=readonly -trimpath -ldflags="-s -w" -o /out/app .

# -----------------------------------------------------------------------------
FROM alpine:3.21 AS runtime

RUN apk add --no-cache ca-certificates \
 && addgroup -g 10001 -S app \
 && adduser  -u 10001 -S app -G app

WORKDIR /app
COPY --from=builder /out/app /app/app

USER 10001

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/app/app"]
