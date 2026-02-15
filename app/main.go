// Copyright 2026 Yoshi Yamaguchi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	"go.opentelemetry.io/otel/trace"
)

func initTracer() (*sdktrace.TracerProvider, error) {
	ctx := context.Background()

	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-gateway:4317"
	}

	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP trace exporter: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String("trace-generator"),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)
	otel.SetTracerProvider(tp)

	return tp, nil
}

func main() {
	tp, err := initTracer()
	if err != nil {
		log.Fatalf("failed to initialize tracer: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	defer func() {
		if err := tp.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	tracer := otel.Tracer("generator")

	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	log.Println("Starting trace generation...")

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			generateTrace(ctx, tracer)
		}
	}
}

func generateTrace(ctx context.Context, tracer trace.Tracer) {
	ctx, span := tracer.Start(ctx, "root-span")
	defer span.End()

	log.Printf("[GEN] TraceID: %s, SpanID: %s, Name: root-span", span.SpanContext().TraceID(), span.SpanContext().SpanID())

	// Generate child spans to test load balancing
	for i := 0; i < 3; i++ {
		_, childSpan := tracer.Start(ctx, fmt.Sprintf("child-span-%d", i))
		log.Printf("[GEN] TraceID: %s, SpanID: %s, Name: child-span-%d", childSpan.SpanContext().TraceID(), childSpan.SpanContext().SpanID(), i)
		time.Sleep(10 * time.Millisecond)
		childSpan.End()
	}

	// Generate slow traces for tail sampling test
	{
		ctx, slowSpan := tracer.Start(ctx, "slow-span")
		log.Printf("[GEN] TraceID: %s, SpanID: %s, Name: slow-span (SLOW)", slowSpan.SpanContext().TraceID(), slowSpan.SpanContext().SpanID())
		time.Sleep(200 * time.Millisecond) // 200ms delay
		slowSpan.End()
		log.Printf("Generated slow trace (>100ms): %s", trace.SpanContextFromContext(ctx).TraceID())
	}

	// Occasionally generate error spans for tail sampling test
	if time.Now().Unix()%5 == 0 {
		_, errSpan := tracer.Start(ctx, "error-span")
		log.Printf("[GEN] TraceID: %s, SpanID: %s, Name: error-span", errSpan.SpanContext().TraceID(), errSpan.SpanContext().SpanID())
		errSpan.SetStatus(1, "intentional error") // 1 is StatusError in OTel Go
		errSpan.End()
		log.Println("Generated error span")
	}
}
