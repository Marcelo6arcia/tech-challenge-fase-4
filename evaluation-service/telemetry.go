package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/bridges/otelslog"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/log/global"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

// setupTelemetry exports every application signal to the Collector over OTLP/HTTP.
// Standard OTEL_EXPORTER_OTLP_* variables configure endpoint, TLS and headers.
func setupTelemetry(ctx context.Context, service string) (func(context.Context) error, error) {
	otel.SetTextMapPropagator(propagation.TraceContext{})
	stdout := slog.NewJSONHandler(os.Stdout, nil)
	slog.SetDefault(slog.New(correlatedHandler{handlers: []slog.Handler{stdout}}))
	if strings.EqualFold(os.Getenv("OTEL_SDK_DISABLED"), "true") {
		return func(context.Context) error { return nil }, nil
	}
	res, err := resource.New(ctx, resource.WithFromEnv(), resource.WithAttributes(
		attribute.String("service.name", service),
		attribute.String("service.namespace", "togglemaster"),
		attribute.String("deployment.environment.name", envOr("DEPLOYMENT_ENVIRONMENT", "dev")),
	))
	if err != nil {
		return nil, err
	}
	var shutdowns []func(context.Context) error
	shutdown := func(ctx context.Context) error {
		var result error
		for _, stop := range shutdowns {
			result = errors.Join(result, stop(ctx))
		}
		return result
	}
	traceExporter, err := otlptracehttp.New(ctx)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(sdktrace.WithResource(res), sdktrace.WithBatcher(traceExporter))
	shutdowns = append(shutdowns, tp.Shutdown)
	metricExporter, err := otlpmetrichttp.New(ctx)
	if err != nil {
		return nil, errors.Join(err, shutdown(ctx))
	}
	mp := sdkmetric.NewMeterProvider(sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)))
	shutdowns = append(shutdowns, mp.Shutdown)
	logExporter, err := otlploghttp.New(ctx)
	if err != nil {
		return nil, errors.Join(err, shutdown(ctx))
	}
	lp := sdklog.NewLoggerProvider(sdklog.WithResource(res),
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExporter)))
	shutdowns = append(shutdowns, lp.Shutdown)
	otel.SetTracerProvider(tp)
	otel.SetMeterProvider(mp)
	global.SetLoggerProvider(lp)
	slog.SetDefault(slog.New(correlatedHandler{handlers: []slog.Handler{
		stdout.WithAttrs([]slog.Attr{slog.Bool("otel_exported", true)}), otelslog.NewHandler("togglemaster", otelslog.WithLoggerProvider(lp)),
	}}))
	return shutdown, nil
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// correlatedHandler keeps stdout useful locally and exports structured logs.
// Only explicit attributes are logged: no headers, API keys or request bodies.
type correlatedHandler struct{ handlers []slog.Handler }

func (h correlatedHandler) Enabled(ctx context.Context, level slog.Level) bool {
	for _, handler := range h.handlers {
		if handler.Enabled(ctx, level) {
			return true
		}
	}
	return false
}

func (h correlatedHandler) Handle(ctx context.Context, record slog.Record) error {
	if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
		record.AddAttrs(slog.String("trace_id", sc.TraceID().String()), slog.String("span_id", sc.SpanID().String()))
	}
	var result error
	for _, handler := range h.handlers {
		if handler.Enabled(ctx, record.Level) {
			result = errors.Join(result, handler.Handle(ctx, record.Clone()))
		}
	}
	return result
}

func (h correlatedHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	next := correlatedHandler{}
	for _, handler := range h.handlers {
		next.handlers = append(next.handlers, handler.WithAttrs(attrs))
	}
	return next
}

func (h correlatedHandler) WithGroup(name string) slog.Handler {
	next := correlatedHandler{}
	for _, handler := range h.handlers {
		next.handlers = append(next.handlers, handler.WithGroup(name))
	}
	return next
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (w *statusRecorder) WriteHeader(status int) {
	if w.status != 0 {
		return
	}
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *statusRecorder) Write(body []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(body)
}

func (w *statusRecorder) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// instrumentHTTP uses bounded route names; query strings and identifiers never
// become labels. Resources and labels are shared with the Python services.
func instrumentHTTP(service string, mux *http.ServeMux) http.Handler {
	meter := otel.Meter("togglemaster/http")
	requests, err := meter.Int64Counter("app.http.requests", metric.WithUnit("{request}"))
	if err != nil {
		panic(err)
	}
	duration, err := meter.Float64Histogram("app.http.duration", metric.WithUnit("s"),
		metric.WithExplicitBucketBoundaries(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10))
	if err != nil {
		panic(err)
	}
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, route := mux.Handler(r)
		if route == "" {
			route = "unmatched"
		}
		method := r.Method
		switch method {
		case "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "CONNECT", "TRACE":
		default:
			method = "OTHER"
		}
		trace.SpanFromContext(r.Context()).SetAttributes(attribute.String("http.route", route))
		trace.SpanFromContext(r.Context()).SetName(method + " " + route)
		started := time.Now()
		recorder := &statusRecorder{ResponseWriter: w}
		defer func() {
			status := recorder.status
			if status == 0 {
				status = http.StatusOK
			}
			attrs := []attribute.KeyValue{
				attribute.String("service.name", service), attribute.String("http.route", route),
				attribute.String("http.request.method", method), attribute.Int("http.response.status_code", status),
			}
			requests.Add(r.Context(), 1, metric.WithAttributes(attrs...))
			duration.Record(r.Context(), time.Since(started).Seconds(), metric.WithAttributes(attrs...))
			slog.InfoContext(r.Context(), "http.request.completed", "service.name", service,
				"http.route", route, "http.request.method", method, "http.response.status_code", status)
		}()
		mux.ServeHTTP(recorder, r)
	})
	return otelhttp.NewHandler(inner, service, otelhttp.WithPropagators(propagation.TraceContext{}))
}

// serveHTTP drains in-flight requests before flushing the providers on SIGTERM.
func serveHTTP(server *http.Server, drain func()) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	errorsCh := make(chan error, 1)
	go func() { errorsCh <- server.ListenAndServe() }()
	select {
	case err := <-errorsCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		err := server.Shutdown(shutdownCtx)
		if drain != nil {
			drain()
		}
		return err
	}
}
