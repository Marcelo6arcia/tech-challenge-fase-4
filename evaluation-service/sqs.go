package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/url"
	"path"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

type EvaluationEvent struct {
	UserID    string    `json:"user_id"`
	FlagName  string    `json:"flag_name"`
	Result    bool      `json:"result"`
	Timestamp time.Time `json:"timestamp"`
}

func (a *App) queueEvaluationEvent(requestCtx context.Context, userID, flagName string, result bool) {
	// Preserve trace context after HTTP cancellation; bound independent work.
	ctx := context.WithoutCancel(requestCtx)
	a.events.Add(1)
	go func() {
		defer a.events.Done()
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		a.sendEvaluationEvent(ctx, userID, flagName, result)
	}()
}

func (a *App) sendEvaluationEvent(ctx context.Context, userID, flagName string, result bool) {
	if a.SqsSvc == nil || a.SqsQueueURL == "" {
		slog.WarnContext(ctx, "evaluation.event.disabled")
		return
	}
	queueName := "evaluation-events"
	if queueURL, err := url.Parse(a.SqsQueueURL); err == nil {
		queueName = path.Base(queueURL.Path)
	}
	ctx, span := otel.Tracer("togglemaster/sqs").Start(ctx, queueName+" send",
		trace.WithSpanKind(trace.SpanKindProducer), trace.WithAttributes(
			attribute.String("messaging.system", "aws_sqs"),
			attribute.String("messaging.destination.name", queueName),
			attribute.String("messaging.operation.name", "send"),
			attribute.String("messaging.operation.type", "send"),
		))
	defer span.End()
	body, err := json.Marshal(EvaluationEvent{UserID: userID, FlagName: flagName, Result: result, Timestamp: time.Now().UTC()})
	if err != nil {
		span.SetStatus(codes.Error, "event serialization failed")
		slog.ErrorContext(ctx, "evaluation.event.serialization.failed")
		return
	}
	carrier := propagation.MapCarrier{}
	propagation.TraceContext{}.Inject(ctx, carrier)
	attributes := make(map[string]*sqs.MessageAttributeValue, len(carrier))
	for name, value := range carrier {
		attributes[name] = &sqs.MessageAttributeValue{DataType: aws.String("String"), StringValue: aws.String(value)}
	}
	_, err = a.SqsSvc.SendMessageWithContext(ctx, &sqs.SendMessageInput{
		MessageBody: aws.String(string(body)), QueueUrl: aws.String(a.SqsQueueURL), MessageAttributes: attributes,
	})
	if err != nil {
		span.SetStatus(codes.Error, "SQS send failed")
		slog.ErrorContext(ctx, "evaluation.event.send.failed")
		return
	}
	slog.InfoContext(ctx, "evaluation.event.sent", "messaging.destination.name", queueName)
}
