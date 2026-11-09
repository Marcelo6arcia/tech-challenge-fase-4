#!/usr/bin/env python3
"""Porta de qualidade do SAST (gosec).

Lê o relatório JSON do gosec e transforma cada achado de severidade alta em uma
anotação do GitHub Actions — visível no Pull Request e na lista de checks, sem
precisar de permissão de admin para abrir o log. Sai com 1 se houver algum.

Uso: python3 .github/scripts/sast_gate.py <relatorio.json> [rotulo]
"""

import json
import os
import pathlib
import sys

ORDEM = {"LOW": 0, "MEDIUM": 1, "HIGH": 2}
SEVERIDADE_MINIMA = "HIGH"
CONFIANCA_MINIMA = "MEDIUM"


def main() -> int:
    if len(sys.argv) < 2:
        print("uso: sast_gate.py <relatorio.json> [rotulo]", file=sys.stderr)
        return 2

    arquivo = pathlib.Path(sys.argv[1])
    rotulo = sys.argv[2] if len(sys.argv) > 2 else "SAST"

    if not arquivo.exists():
        print(f"Relatório do gosec não encontrado: {arquivo}", file=sys.stderr)
        return 1

    relatorio = json.loads(arquivo.read_text() or "{}")
    todos = relatorio.get("Issues") or []

    achados = [
        i
        for i in todos
        if ORDEM.get((i.get("severity") or "").upper(), 0) >= ORDEM[SEVERIDADE_MINIMA]
        and ORDEM.get((i.get("confidence") or "").upper(), 0) >= ORDEM[CONFIANCA_MINIMA]
    ]

    resumo = os.environ.get("GITHUB_STEP_SUMMARY")

    if not achados:
        print(
            f"{rotulo}: nenhum achado de severidade {SEVERIDADE_MINIMA} "
            f"({len(todos)} achado(s) de severidade menor, registrados no SARIF)."
        )
        if resumo:
            with open(resumo, "a", encoding="utf-8") as fh:
                fh.write(f"### {rotulo}: sem achados de severidade alta\n")
        return 0

    for i in achados:
        arquivo_rel = i.get("file", "?")
        linha = str(i.get("line", "0")).split("-")[0]
        print(
            f"::error file={arquivo_rel},line={linha},"
            f"title={rotulo} {i.get('rule_id', '?')}::"
            f"{i.get('details', '').strip()} "
            f"[severidade {i.get('severity')}, confiança {i.get('confidence')}]"
        )

    if resumo:
        with open(resumo, "a", encoding="utf-8") as fh:
            fh.write(f"### {rotulo} reprovou: {len(achados)} achado(s) de severidade alta\n\n")
            fh.write("| Regra | Arquivo | Linha | Descrição |\n|---|---|---|---|\n")
            for i in achados:
                fh.write(
                    f"| {i.get('rule_id','?')} | `{i.get('file','?')}` "
                    f"| {i.get('line','?')} | {i.get('details','').strip()} |\n"
                )

    print(f"\n{len(achados)} achado(s) de severidade alta — build reprovado.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
