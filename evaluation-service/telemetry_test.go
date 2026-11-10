package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
	"go.opentelemetry.io/otel/trace"
	collectlogs "go.opentelemetry.io/proto/otlp/collector/logs/v1"
	collectmetrics "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	collecttraces "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	"google.golang.org/protobuf/proto"
)

func TestResponseTraceIDMatchesServerRoot(t *testing.T) {
	exporter := tracetest.NewInMemoryExporter()
	provider := sdktrace.NewTracerProvider(sdktrace.WithSyncer(exporter))
	previous := otel.GetTracerProvider()
	otel.SetTracerProvider(provider)
	t.Cleanup(func() {
		otel.SetTracerProvider(previous)
		_ = provider.Shutdown(context.Background())
	})
	mux := http.NewServeMux()
	mux.HandleFunc("/evaluate", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodGet, "/evaluate", nil)
	req.Header.Set("X-Trace-Id", "caller-value-must-not-be-echoed")
	response := httptest.NewRecorder()
	instrumentHTTP("evaluation-service", mux).ServeHTTP(response, req)
	spans := exporter.GetSpans()
	if len(spans) != 1 {
		t.Fatalf("expected one exported server span, got %d", len(spans))
	}
	span := spans[0]
	if span.SpanKind != trace.SpanKindServer || span.Parent.IsValid() {
		t.Fatal("request without traceparent must start a real server root")
	}
	if got := response.Result().Header.Get("X-Trace-Id"); got != span.SpanContext.TraceID().String() {
		t.Fatalf("response trace ID does not match exported span: %q", got)
	}
}

// This is an OTLP wire-level contract test: three real exporters send protobuf
// to a local receiver. No Collector, cloud credentials or AWS resources are used.
func TestTelemetryExportsThreeSignalsWithCorrelation(t *testing.T) {
	var mu sync.Mutex
	received := map[string][][]byte{}
	receiver := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		mu.Lock()
		received[r.URL.Path] = append(received[r.URL.Path], body)
		mu.Unlock()
		w.Header().Set("Content-Type", "application/x-protobuf")
		w.WriteHeader(http.StatusOK)
	}))
	defer receiver.Close()
	t.Setenv("OTEL_SDK_DISABLED", "false")
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", receiver.URL)
	t.Setenv("OTEL_EXPORTER_OTLP_PROTOCOL", "http/protobuf")
	for _, signal := range []string{"TRACES", "METRICS", "LOGS"} {
		t.Setenv("OTEL_EXPORTER_OTLP_"+signal+"_ENDPOINT", "")
		t.Setenv("OTEL_EXPORTER_OTLP_"+signal+"_HEADERS", "")
	}
	shutdown, err := setupTelemetry(context.Background(), "evaluation-service")
	if err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/validate", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusServiceUnavailable) })
	handler := instrumentHTTP("evaluation-service", mux)
	req := httptest.NewRequest(http.MethodGet, "/validate", nil)
	req.Header.Set("traceparent", "00-0123456789abcdef0123456789abcdef-0123456789abcdef-01")
	req.Header.Set("Authorization", "Bearer must-never-appear-in-telemetry")
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatal(recorder.Code)
	}
	if err := shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	for _, signal := range []string{"traces", "metrics", "logs"} {
		if len(received["/v1/"+signal]) == 0 {
			t.Fatalf("missing OTLP %s", signal)
		}
	}
	var traces collecttraces.ExportTraceServiceRequest
	if err := proto.Unmarshal(received["/v1/traces"][0], &traces); err != nil {
		t.Fatal(err)
	}
	span := traces.ResourceSpans[0].ScopeSpans[0].Spans[0]
	if string(span.TraceId) != string([]byte{1, 35, 69, 103, 137, 171, 205, 239, 1, 35, 69, 103, 137, 171, 205, 239}) {
		t.Fatalf("trace context lost: %x", span.TraceId)
	}
	var logs collectlogs.ExportLogsServiceRequest
	if err := proto.Unmarshal(received["/v1/logs"][0], &logs); err != nil {
		t.Fatal(err)
	}
	logRecord := logs.ResourceLogs[0].ScopeLogs[0].LogRecords[0]
	if string(logRecord.TraceId) != string(span.TraceId) || string(logRecord.SpanId) != string(span.SpanId) {
		t.Fatal("log is not correlated to server span")
	}
	var metrics collectmetrics.ExportMetricsServiceRequest
	if err := proto.Unmarshal(received["/v1/metrics"][0], &metrics); err != nil {
		t.Fatal(err)
	}
	foundCounter, foundHistogram, foundService := false, false, false
	for _, resourceMetrics := range metrics.ResourceMetrics {
		for _, attr := range resourceMetrics.Resource.Attributes {
			if attr.Key == "service.name" && attr.Value.GetStringValue() == "evaluation-service" {
				foundService = true
			}
		}
		for _, scope := range resourceMetrics.ScopeMetrics {
			for _, m := range scope.Metrics {
				switch m.Name {
				case "app.http.requests":
					for _, dp := range m.GetSum().DataPoints {
						if dp.GetAsInt() != 1 {
							t.Fatalf("counter=%d", dp.GetAsInt())
						}
						labels := map[string]string{}
						status := int64(0)
						for _, attr := range dp.Attributes {
							labels[attr.Key] = attr.Value.GetStringValue()
							if attr.Key == "http.response.status_code" {
								status = attr.Value.GetIntValue()
							}
						}
						if labels["http.route"] != "/validate" || labels["http.request.method"] != "GET" || status != 503 {
							t.Fatalf("incorrect metric labels: %v status=%d", labels, status)
						}
					}
					foundCounter = true
				case "app.http.duration":
					foundHistogram = m.Unit == "s" && len(m.GetHistogram().DataPoints) > 0
				}
			}
		}
	}
	if !foundCounter || !foundHistogram || !foundService {
		t.Fatalf("missing metric contract: counter=%v histogram=%v resource=%v", foundCounter, foundHistogram, foundService)
	}
	for _, bodies := range received {
		for _, body := range bodies {
			if strings.Contains(string(body), "must-never-appear") {
				t.Fatal("secret leaked into telemetry")
			}
		}
	}
}

func TestDisabledTelemetryDoesNotCreateExporters(t *testing.T) {
	t.Setenv("OTEL_SDK_DISABLED", "true")
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", ":invalid-endpoint")
	shutdown, err := setupTelemetry(context.Background(), "evaluation-service")
	if err != nil {
		t.Fatal(err)
	}
	if err := shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
}
