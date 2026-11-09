package main

import (
	"fmt"
	"strings"
	"testing"
)

func TestGetDeterministicBucketDentroDoIntervalo(t *testing.T) {
	for i := 0; i < 1000; i++ {
		bucket := getDeterministicBucket(fmt.Sprintf("usuario-%d:minha-flag", i))
		if bucket < 0 || bucket > 99 {
			t.Fatalf("bucket fora de 0..99: %d", bucket)
		}
	}
}

func TestGetDeterministicBucketEstavel(t *testing.T) {
	const entrada = "usuario-42minha-flag"

	primeiro := getDeterministicBucket(entrada)
	for i := 0; i < 10; i++ {
		if got := getDeterministicBucket(entrada); got != primeiro {
			t.Fatalf("bucket instável: %d != %d", got, primeiro)
		}
	}
}

func TestGetDeterministicBucketDistribuicao(t *testing.T) {
	// Com 10.000 usuários, uma faixa de 10% deve receber algo próximo de 1.000.
	// Tolerância larga (±25%) para o teste não ficar frágil.
	const total = 10000
	dentro := 0

	for i := 0; i < total; i++ {
		if getDeterministicBucket(fmt.Sprintf("user-%d", i)) < 10 {
			dentro++
		}
	}

	if dentro < 750 || dentro > 1250 {
		t.Errorf("distribuição enviesada: %d de %d na faixa de 10%%", dentro, total)
	}
}

func TestRunEvaluationLogicFlagDesligada(t *testing.T) {
	app := &App{}

	info := &CombinedFlagInfo{
		Flag: &Flag{Name: "nova-home", IsEnabled: false},
	}

	if app.runEvaluationLogic(info, "usuario-1") {
		t.Error("flag desligada deveria avaliar como false")
	}
}

func TestRunEvaluationLogicFlagInexistente(t *testing.T) {
	app := &App{}

	if app.runEvaluationLogic(&CombinedFlagInfo{}, "usuario-1") {
		t.Error("flag inexistente deveria avaliar como false")
	}
}

func TestRunEvaluationLogicSemRegraLiberaTodos(t *testing.T) {
	app := &App{}

	info := &CombinedFlagInfo{
		Flag: &Flag{Name: "nova-home", IsEnabled: true},
		Rule: nil,
	}

	if !app.runEvaluationLogic(info, "usuario-1") {
		t.Error("flag ligada sem regra deveria avaliar como true")
	}
}

func TestRunEvaluationLogicRegraDesabilitada(t *testing.T) {
	app := &App{}

	info := &CombinedFlagInfo{
		Flag: &Flag{Name: "nova-home", IsEnabled: true},
		Rule: &TargetingRule{IsEnabled: false, Rules: Rule{Type: "PERCENTAGE", Value: float64(0)}},
	}

	if !app.runEvaluationLogic(info, "usuario-1") {
		t.Error("regra desabilitada deveria liberar a flag")
	}
}

func TestRunEvaluationLogicRolloutZeroECem(t *testing.T) {
	app := &App{}

	casos := []struct {
		nome       string
		percentual float64
		esperado   bool
	}{
		{"rollout de 0% nega todos", 0, false},
		{"rollout de 100% libera todos", 100, true},
	}

	for _, c := range casos {
		t.Run(c.nome, func(t *testing.T) {
			info := &CombinedFlagInfo{
				Flag: &Flag{Name: "nova-home", IsEnabled: true},
				Rule: &TargetingRule{
					IsEnabled: true,
					Rules:     Rule{Type: "PERCENTAGE", Value: c.percentual},
				},
			}

			for i := 0; i < 200; i++ {
				got := app.runEvaluationLogic(info, fmt.Sprintf("usuario-%d", i))
				if got != c.esperado {
					t.Fatalf("usuario-%d: got %v, esperado %v", i, got, c.esperado)
				}
			}
		})
	}
}

func TestRunEvaluationLogicValorInvalido(t *testing.T) {
	app := &App{}

	info := &CombinedFlagInfo{
		Flag: &Flag{Name: "nova-home", IsEnabled: true},
		Rule: &TargetingRule{
			IsEnabled: true,
			// O JSON traz uma string onde deveria vir um número
			Rules: Rule{Type: "PERCENTAGE", Value: "cinquenta"},
		},
	}

	if app.runEvaluationLogic(info, "usuario-1") {
		t.Error("valor de regra inválido deveria resultar em false (fail closed)")
	}
}

func TestRunEvaluationLogicMesmoUsuarioMesmaDecisao(t *testing.T) {
	app := &App{}

	info := &CombinedFlagInfo{
		Flag: &Flag{Name: "nova-home", IsEnabled: true},
		Rule: &TargetingRule{
			IsEnabled: true,
			Rules:     Rule{Type: "PERCENTAGE", Value: float64(50)},
		},
	}

	primeiro := app.runEvaluationLogic(info, "usuario-estavel")
	for i := 0; i < 20; i++ {
		if got := app.runEvaluationLogic(info, "usuario-estavel"); got != primeiro {
			t.Fatal("a decisão variou para o mesmo usuário e a mesma flag")
		}
	}
}

func TestSanitizarParaLogRemoveQuebrasDeLinha(t *testing.T) {
	// Um flag_name com "\n" permitiria forjar uma linha de log inteira.
	entrada := "nova-home\nINFO: usuario admin autenticado com sucesso"

	got := sanitizarParaLog(entrada)

	if strings.ContainsAny(got, "\n\r") {
		t.Errorf("saída ainda contém quebra de linha: %q", got)
	}
	if want := "nova-homeINFO: usuario admin autenticado com sucesso"; got != want {
		t.Errorf("sanitizarParaLog(%q) = %q, esperado %q", entrada, got, want)
	}
}

func TestSanitizarParaLogRemoveCaracteresDeControle(t *testing.T) {
	got := sanitizarParaLog("flag\x00nula\x07sino\x1bescape")

	if want := "flagnulasinoescape"; got != want {
		t.Errorf("got %q, esperado %q", got, want)
	}
}

func TestSanitizarParaLogTruncaValorLongo(t *testing.T) {
	got := sanitizarParaLog(strings.Repeat("a", 500))

	if want := 120 + len("..."); len(got) != want {
		t.Errorf("tamanho = %d, esperado %d", len(got), want)
	}
	if !strings.HasSuffix(got, "...") {
		t.Error("valor truncado deveria terminar em reticências")
	}
}

func TestSanitizarParaLogPreservaTextoNormal(t *testing.T) {
	const entrada = "checkout-novo_v2"

	if got := sanitizarParaLog(entrada); got != entrada {
		t.Errorf("sanitizarParaLog(%q) = %q — não deveria alterar", entrada, got)
	}
}
