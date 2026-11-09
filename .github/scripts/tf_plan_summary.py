"""Publica somente ações e tipos do plano, sem valores de recurso ou outputs."""

import collections
import json
import sys


def summarize(plan):
    counts = collections.Counter()
    for resource in plan.get("resource_changes", []):
        actions = resource["change"]["actions"]
        if actions == ["no-op"]:
            continue
        counts[(resource["type"], ", ".join(actions))] += 1
    lines = ["### Terraform: resumo do plano", "", "| Tipo | Ações | Quantidade |", "|---|---|---:|"]
    lines.extend(f"| {kind} | {actions} | {count} |" for (kind, actions), count in sorted(counts.items()))
    if not counts:
        lines.append("| — | Sem mudanças | 0 |")
    lines.extend(["", "Plano completo arquivado com criptografia; valores e outputs não são publicados."])
    return "\n".join(lines)


if __name__ == "__main__":
    print(summarize(json.load(sys.stdin)))
