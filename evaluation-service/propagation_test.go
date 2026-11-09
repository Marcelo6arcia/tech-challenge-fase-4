package main

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/service/sqs"
	"github.com/aws/aws-sdk-go/service/sqs/sqsiface"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
	"go.opentelemetry.io/otel/trace"
)

type sqsObservation struct {
	input    *sqs.SendMessageInput
	canceled bool
	deadline bool
}
type fakeSQS struct {
	sqsiface.SQSAPI
	sent chan sqsObservation
}

func (f *fakeSQS) SendMessageWithContext(ctx aws.Context, input *sqs.SendMessageInput, _ ...request.Option) (*sqs.SendMessageOutput, error) {
	_, deadline := ctx.Deadline()
	f.sent <- sqsObservation{input: input, canceled: ctx.Err() != nil, deadline: deadline}
	return &sqs.SendMessageOutput{}, nil
}

func traceTestProvider(t *testing.T) *tracetest.InMemoryExporter {
	t.Helper()
	exporter := tracetest.NewInMemoryExporter()
	provider := sdktrace.NewTracerProvider(sdktrace.WithSyncer(exporter))
	previous := otel.GetTracerProvider()
	otel.SetTracerProvider(provider)
	otel.SetTextMapPropagator(propagation.TraceContext{})
	t.Cleanup(func() { otel.SetTracerProvider(previous); _ = provider.Shutdown(context.Background()) })
	return exporter
}

func TestAsyncSQSPropagatesTraceAfterRequestCancellation(t *testing.T) {
	exporter := traceTestProvider(t)
	state, _ := trace.ParseTraceState("testvendor=value")
	remote := trace.NewSpanContext(trace.SpanContextConfig{TraceID: trace.TraceID{1, 2, 3}, SpanID: trace.SpanID{4, 5, 6}, TraceFlags: trace.FlagsSampled, TraceState: state, Remote: true})
	ctx, parent := otel.Tracer("test").Start(trace.ContextWithRemoteSpanContext(context.Background(), remote), "incoming")
	ctx, cancel := context.WithCancel(ctx)
	parentID := parent.SpanContext().SpanID()
	cancel()
	parent.End()
	sqsClient := &fakeSQS{sent: make(chan sqsObservation, 1)}
	app := &App{SqsSvc: sqsClient, SqsQueueURL: "https://sqs.us-east-1.amazonaws.com/000000000000/evaluations"}
	app.queueEvaluationEvent(ctx, "synthetic-user", "demo-flag", true)
	app.events.Wait()
	select {
	case observed := <-sqsClient.sent:
		if observed.canceled || !observed.deadline {
			t.Fatal("request cancellation leaked or bounded deadline missing")
		}
		carrier := propagation.MapCarrier{}
		for name, attr := range observed.input.MessageAttributes {
			if aws.StringValue(attr.DataType) != "String" {
				t.Fatal("invalid message attribute type")
			}
			carrier[name] = aws.StringValue(attr.StringValue)
		}
		extracted := trace.SpanContextFromContext(propagation.TraceContext{}.Extract(context.Background(), carrier))
		if extracted.TraceID() != remote.TraceID() || extracted.TraceState().String() != "testvendor=value" {
			t.Fatalf("propagation lost: %v", carrier)
		}
		if _, exists := carrier["baggage"]; exists {
			t.Fatal("unexpected baggage")
		}
	case <-time.After(time.Second):
		t.Fatal("SQS not called")
	}
	spans := exporter.GetSpans()
	if len(spans) != 2 {
		t.Fatalf("spans=%d", len(spans))
	}
	producer := spans[1]
	if producer.SpanKind != trace.SpanKindProducer || producer.Parent.SpanID() != parentID {
		t.Fatal("producer not linked to HTTP parent")
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestUpstreamHTTPPropagatesParentTrace(t *testing.T) {
	traceTestProvider(t)
	ctx, parent := otel.Tracer("test").Start(context.Background(), "evaluate")
	defer parent.End()
	var got trace.SpanContext
	transport := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		got = trace.SpanContextFromContext(propagation.TraceContext{}.Extract(r.Context(), propagation.HeaderCarrier(r.Header)))
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"name":"demo","is_enabled":true}`)), Header: make(http.Header), Request: r}, nil
	})
	app := &App{FlagServiceURL: "http://flag-service:8080", HttpClient: &http.Client{Transport: otelhttp.NewTransport(transport)}}
	flag, err := app.fetchFlag(ctx, "demo")
	if err != nil || flag.Name != "demo" {
		t.Fatalf("fetch=%v err=%v", flag, err)
	}
	if got.TraceID() != parent.SpanContext().TraceID() || got.SpanID() == parent.SpanContext().SpanID() {
		t.Fatal("HTTP client span propagation failed")
	}
}
