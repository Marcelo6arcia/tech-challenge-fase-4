package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"sync/atomic"
	"time"

	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
)

// App struct (para injeção de dependência)
type App struct {
	DB               *sql.DB
	MasterKey        string
	DemoFaultEnabled bool
	demoFault        atomic.Bool
}

func main() {
	// Carrega o .env para desenvolvimento local. Em produção, isso não fará nada.
	_ = godotenv.Load()
	shutdown, err := setupTelemetry(context.Background(), "auth-service")
	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := shutdown(ctx); err != nil {
			log.Printf("Telemetry shutdown: %v", err)
		}
	}()

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8001" // Porta padrão
	}

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL deve ser definida")
	}

	masterKey := os.Getenv("MASTER_KEY")
	if masterKey == "" {
		log.Fatal("MASTER_KEY deve ser definida")
	}

	// --- Conexão com o Banco ---
	db, err := connectDB(databaseURL)
	if err != nil {
		log.Fatalf("Não foi possível conectar ao banco de dados: %v", err)
	}
	defer func() { _ = db.Close() }()

	app := &App{
		DB:               db,
		MasterKey:        masterKey,
		DemoFaultEnabled: os.Getenv("DEMO_FAULT_ENABLED") == "true",
	}

	// --- Rotas da API ---
	handler := instrumentHTTP("auth-service", app.routes())

	// gosec G706: `port` vem de variável de ambiente definida pelo ConfigMap
	// do deployment, não de entrada de usuário.
	log.Printf("Serviço de Autenticação (Go) rodando na porta %s", port) //nolint:gosec
	// gosec G114: ListenAndServe sem timeouts deixa a porta aberta a Slowloris —
	// conexões que enviam bytes lentamente e prendem goroutines indefinidamente.
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	if err := serveHTTP(srv, nil); err != nil {
		log.Printf("HTTP server stopped: %v", err)
	}
}

func (a *App) routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", a.healthHandler)
	mux.HandleFunc("/validate", a.validateKeyHandler)
	mux.Handle("/admin/keys", a.masterKeyAuthMiddleware(http.HandlerFunc(a.createKeyHandler)))
	mux.HandleFunc("/admin/demo/fault", a.demoFaultHandler)
	return mux
}

// connectDB inicializa e testa a conexão com o PostgreSQL
func connectDB(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, err
	}

	if err = db.Ping(); err != nil {
		return nil, err
	}

	log.Println("Conectado ao PostgreSQL com sucesso!")
	return db, nil
}
