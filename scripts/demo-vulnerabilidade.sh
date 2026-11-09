#!/usr/bin/env bash
# =============================================================================
# demo-vulnerabilidade.sh — insere ou remove uma vulnerabilidade proposital
# para demonstrar a porta de qualidade do pipeline DevSecOps.
#
#   ./scripts/demo-vulnerabilidade.sh inserir flag-service
#   ./scripts/demo-vulnerabilidade.sh remover flag-service
#
# Serviços Python  -> dependência com CVE CRITICAL (falha no job SCA)
# Serviços Go      -> comando de shell com entrada do usuário (falha no SAST)
# =============================================================================
set -euo pipefail

ACAO="${1:-}"
SERVICO="${2:-}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PYTHON_SERVICES="flag-service targeting-service analytics-service"
GO_SERVICES="auth-service evaluation-service"

MARCADOR="# === DEMO DE VULNERABILIDADE - REMOVER ANTES DO MERGE ==="
DEP_VULNERAVEL="PyYAML==5.3.1"
DEP_CORRIGIDA="PyYAML==6.0.2"
ARQUIVO_GO_DEMO="vuln_demo.go"

uso() {
  cat <<EOF
Uso: $0 <inserir|corrigir|remover> <servico>

Serviços disponíveis:
  Python (demo de SCA):  ${PYTHON_SERVICES}
  Go     (demo de SAST): ${GO_SERVICES}

Ações:
  inserir   introduz a falha — o pipeline deve REPROVAR
  corrigir  sobe a dependência para a versão com patch — o pipeline PASSA e,
            o que importa para a demonstração, o merge gera mudança liquida
  remover   desfaz tudo, para limpar o repositorio depois da gravacao

Use 'corrigir', e nao 'remover', como passo de correcao no video. Inserir e
depois remover no mesmo Pull Request da saldo liquido ZERO: o merge na main nao
altera arquivo nenhum, os workflows filtram por 'paths', nenhum filtro casa e o
pipeline da main NAO RODA. O bloco de GitOps fica sem o commit de deploy para
mostrar.

'corrigir' tambem conta a historia certa: a resposta a uma CVE e subir a
dependencia para a versao corrigida, nao remover a dependencia nem afrouxar o
portao.

Exemplos:
  $0 inserir flag-service      # PyYAML 5.3.1 (CVE-2020-14343, CVSS 9.8) — reprova
  $0 corrigir flag-service     # PyYAML 6.0.2 — passa, e o merge dispara o deploy
  $0 remover flag-service      # limpeza pos-gravacao
  $0 inserir auth-service      # exec.Command com entrada do usuario (gosec G204)
  $0 remover auth-service
EOF
  exit 1
}

[[ -z "$ACAO" || -z "$SERVICO" ]] && uso
[[ ! -d "$RAIZ/$SERVICO" ]] && { echo "Serviço '$SERVICO' não encontrado."; uso; }

e_python() { [[ " $PYTHON_SERVICES " == *" $SERVICO "* ]]; }
e_go()     { [[ " $GO_SERVICES "     == *" $SERVICO "* ]]; }

# -----------------------------------------------------------------------------
inserir_python() {
  local req="$RAIZ/$SERVICO/requirements.txt"

  if grep -q "$MARCADOR" "$req"; then
    echo "A vulnerabilidade já está presente em $SERVICO."
    return
  fi

  # Tira qualquer PyYAML que ja esteja no arquivo antes de acrescentar o
  # vulneravel. Sem isso, um `inserir` depois de um `corrigir` deixa dois pins
  # do mesmo pacote e o pip reprova ANTES do portao de SCA:
  #
  #   ERROR: Cannot install PyYAML==5.3.1 and PyYAML==6.0.2 because these
  #   package versions have conflicting dependencies.
  #
  # O job que falha vira "Build & Unit Test" em vez de "SCA", e a demonstracao
  # passa a mostrar erro de dependencia quebrada -- nao uma CVE sendo barrada.
  # E o ciclo inserir -> corrigir -> inserir e o que acontece em qualquer
  # segunda tomada da gravacao.
  python3 - "$req" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
linhas = p.read_text().splitlines()
saida, i = [], 0
while i < len(linhas):
    if re.match(r"^\s*PyYAML\s*==", linhas[i], re.IGNORECASE):
        # remove tambem o bloco de comentario colado acima da linha
        while saida and saida[-1].lstrip().startswith("#"):
            saida.pop()
        while saida and saida[-1].strip() == "":
            saida.pop()
        i += 1
        continue
    saida.append(linhas[i])
    i += 1
p.write_text("\n".join(saida).rstrip("\n") + "\n")
PY

  cat >> "$req" <<EOF

$MARCADOR
# CVE-2020-14343 (CVSS 9.8, CRITICAL): execucao arbitraria de codigo via
# yaml.full_load. Corrigida a partir da 5.4.
$DEP_VULNERAVEL
EOF

  echo "Dependência vulnerável adicionada em $SERVICO/requirements.txt"
  echo "O job SCA deve falhar com CVE-2020-14343."
}

corrigir_python() {
  local req="$RAIZ/$SERVICO/requirements.txt"

  if ! grep -q "$DEP_VULNERAVEL" "$req"; then
    echo "A dependência vulnerável não está presente em $SERVICO — nada a corrigir."
    return
  fi

  python3 - "$req" "$DEP_VULNERAVEL" "$DEP_CORRIGIDA" <<'PY'
import sys, pathlib
caminho, vulneravel, corrigida = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(caminho)
texto = p.read_text()
texto = texto.replace(
    "# CVE-2020-14343 (CVSS 9.8, CRITICAL): execucao arbitraria de codigo via\n"
    "# yaml.full_load. Corrigida a partir da 5.4.\n",
    "# Bump exigido pelo SCA: a 5.3.1 carregava a CVE-2020-14343 (CVSS 9.8),\n"
    "# execucao arbitraria de codigo via yaml.full_load.\n",
)
texto = texto.replace(vulneravel, corrigida)
p.write_text(texto)
PY

  # O marcador vira outra coisa: a linha deixa de ser demonstracao e passa a ser
  # uma dependencia legitima, na versao corrigida.
  python3 - "$req" "$MARCADOR" <<'PY'
import sys, pathlib
caminho, marcador = sys.argv[1], sys.argv[2]
p = pathlib.Path(caminho)
p.write_text(p.read_text().replace(marcador + "\n", ""))
PY

  echo "Dependência corrigida em $SERVICO: ${DEP_VULNERAVEL} -> ${DEP_CORRIGIDA}"
  echo "O job SCA deve passar, e o merge na main vai gerar mudanca liquida —"
  echo "entao o pipeline da main roda e publica no ECR."
}

remover_python() {
  local req="$RAIZ/$SERVICO/requirements.txt"

  # Remove qualquer PyYAML e o bloco de comentario colado nele, venha de
  # `inserir` (5.3.1, com marcador) ou de `corrigir` (6.0.2, sem marcador). A
  # versao anterior procurava so o marcador, entao depois de um `corrigir` ela
  # respondia "Nada a remover" e deixava a dependencia para tras -- o pacote
  # nem e usado pelo flag-service, so existe para a demonstracao.
  python3 - "$req" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
linhas = p.read_text().splitlines()
saida, removeu, i = [], False, 0
while i < len(linhas):
    if re.match(r"^\s*PyYAML\s*==", linhas[i], re.IGNORECASE):
        while saida and saida[-1].lstrip().startswith("#"):
            saida.pop()
        while saida and saida[-1].strip() == "":
            saida.pop()
        removeu, i = True, i + 1
        continue
    saida.append(linhas[i])
    i += 1
p.write_text("\n".join(saida).rstrip("\n") + "\n")
print("Dependência de demonstração removida." if removeu else "Nada a remover.")
PY
}

# -----------------------------------------------------------------------------
inserir_go() {
  local arquivo="$RAIZ/$SERVICO/$ARQUIVO_GO_DEMO"

  if [[ -f "$arquivo" ]]; then
    echo "A vulnerabilidade já está presente em $SERVICO."
    return
  fi

  cat > "$arquivo" <<'EOF'
package main

// === DEMO DE VULNERABILIDADE - REMOVER ANTES DO MERGE ===
//
// gosec G204: Subprocess launched with a potential tainted input.
// O valor do parâmetro `host` vem direto da query string e é entregue ao shell:
// `?host=8.8.8.8;cat /etc/passwd` executaria o segundo comando.
//
// Este arquivo existe apenas para demonstrar a porta de qualidade de SAST.

import (
	"net/http"
	"os/exec"
)

func demoVulneravelHandler(w http.ResponseWriter, r *http.Request) {
	host := r.URL.Query().Get("host")

	saida, err := exec.Command("sh", "-c", "ping -c 1 "+host).Output()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	_, _ = w.Write(saida)
}
EOF

  echo "Arquivo $SERVICO/$ARQUIVO_GO_DEMO criado."
  echo "O job SAST deve falhar com gosec G204."
}

remover_go() {
  local arquivo="$RAIZ/$SERVICO/$ARQUIVO_GO_DEMO"

  if [[ -f "$arquivo" ]]; then
    rm "$arquivo"
    echo "Arquivo de demonstração removido."
  else
    echo "Nada a remover."
  fi
}

# -----------------------------------------------------------------------------
case "$ACAO" in
  inserir)
    if e_python; then inserir_python
    elif e_go;   then inserir_go
    else uso; fi
    ;;
  corrigir)
    if e_python; then corrigir_python
    elif e_go;   then remover_go   # em Go a correcao e tirar o exec.Command
    else uso; fi
    ;;
  remover)
    if e_python; then remover_python
    elif e_go;   then remover_go
    else uso; fi
    ;;
  *)
    uso
    ;;
esac

echo
echo "Diferença gerada:"
git -C "$RAIZ" --no-pager diff --stat -- "$SERVICO" || true
