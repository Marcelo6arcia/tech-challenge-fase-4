package main

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

func TestGenerateAPIKeyFormato(t *testing.T) {
	key, err := generateAPIKey()
	if err != nil {
		t.Fatalf("generateAPIKey devolveu erro: %v", err)
	}

	if !strings.HasPrefix(key, "tm_key_") {
		t.Errorf("chave sem o prefixo esperado: %q", key)
	}

	// 32 bytes em hexadecimal = 64 caracteres, mais o prefixo
	if got, want := len(key), len("tm_key_")+64; got != want {
		t.Errorf("tamanho da chave = %d, esperado %d", got, want)
	}

	if _, err := hex.DecodeString(strings.TrimPrefix(key, "tm_key_")); err != nil {
		t.Errorf("corpo da chave não é hexadecimal válido: %v", err)
	}
}

func TestGenerateAPIKeyNaoRepete(t *testing.T) {
	vistas := make(map[string]struct{}, 100)

	for i := 0; i < 100; i++ {
		key, err := generateAPIKey()
		if err != nil {
			t.Fatalf("generateAPIKey devolveu erro na iteração %d: %v", i, err)
		}
		if _, dup := vistas[key]; dup {
			t.Fatalf("chave repetida gerada na iteração %d", i)
		}
		vistas[key] = struct{}{}
	}
}

func TestHashAPIKeyEhSHA256(t *testing.T) {
	const entrada = "tm_key_teste"

	esperado := sha256.Sum256([]byte(entrada))
	if got, want := hashAPIKey(entrada), hex.EncodeToString(esperado[:]); got != want {
		t.Errorf("hashAPIKey(%q) = %q, esperado %q", entrada, got, want)
	}
}

func TestHashAPIKeyDeterministicoETamanho(t *testing.T) {
	const entrada = "tm_key_abc123"

	primeiro := hashAPIKey(entrada)
	segundo := hashAPIKey(entrada)

	if primeiro != segundo {
		t.Error("hashAPIKey não é determinístico")
	}

	// A coluna key_hash do banco é VARCHAR(64): o hash não pode passar disso.
	if len(primeiro) != 64 {
		t.Errorf("tamanho do hash = %d, esperado 64", len(primeiro))
	}
}

func TestHashAPIKeyEntradasDiferentes(t *testing.T) {
	if hashAPIKey("chave-a") == hashAPIKey("chave-b") {
		t.Error("chaves diferentes produziram o mesmo hash")
	}
}
