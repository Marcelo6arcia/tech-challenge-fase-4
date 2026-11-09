#!/usr/bin/env python3
"""Porta de qualidade do SCA.

Lê o relatório JSON do Trivy e transforma cada vulnerabilidade CRITICAL em uma
anotação do GitHub Actions, visível no Pull Request e na lista de checks — sem
precisar abrir o log do job. Sai com 1 se houver qualquer achado.

Uso: python3 .github/scripts/sca_gate.py <relatorio.json> [rotulo]
"""

import json
import os
import pathlib
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("uso: sca_gate.py <relatorio.json> [rotulo]", file=sys.stderr)
        return 2

    arquivo = pathlib.Path(sys.argv[1])
    rotulo = sys.argv[2] if len(sys.argv) > 2 else "SCA"

    if not arquivo.exists():
        print(f"Relatório do Trivy não encontrado: {arquivo}", file=sys.stderr)
        return 1

    relatorio = json.loads(arquivo.read_text() or "{}")

    achados = []
    for resultado in relatorio.get("Results") or []:
        alvo = resultado.get("Target", "")
        for v in resultado.get("Vulnerabilities") or []:
            achados.append(
                {
                    "alvo": alvo,
                    "pacote": v.get("PkgName", "?"),
                    "instalada": v.get("InstalledVersion", "?"),
                    "corrigida": v.get("FixedVersion") or "sem correção publicada",
                    "id": v.get("VulnerabilityID", "?"),
                    "titulo": (v.get("Title") or "").strip()[:120],
                }
            )

    resumo = os.environ.get("GITHUB_STEP_SUMMARY")

    if not achados:
        print(f"{rotulo}: nenhuma vulnerabilidade CRITICAL com correção disponível.")
        if resumo:
            with open(resumo, "a", encoding="utf-8") as fh:
                fh.write(f"### {rotulo}: nenhuma dependência CRITICAL\n")
        return 0

    for a in achados:
        print(
            f"::error title={rotulo} {a['id']}::{a['pacote']} {a['instalada']} "
            f"-> corrigido em {a['corrigida']} ({a['alvo']}). {a['titulo']}"
        )

    if resumo:
        with open(resumo, "a", encoding="utf-8") as fh:
            fh.write(f"### {rotulo} reprovou: {len(achados)} achado(s) CRITICAL\n\n")
            fh.write("| Pacote | Instalada | Corrigida em | CVE | Alvo |\n")
            fh.write("|---|---|---|---|---|\n")
            for a in achados:
                fh.write(
                    f"| `{a['pacote']}` | `{a['instalada']}` | `{a['corrigida']}` "
                    f"| {a['id']} | `{a['alvo']}` |\n"
                )

    print(f"\n{len(achados)} vulnerabilidade(s) CRITICAL — build reprovado.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
