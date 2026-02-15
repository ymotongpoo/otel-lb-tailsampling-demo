# Copyright 2026 Yoshi Yamaguchi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

FROM golang:1.24-bookworm AS builder
RUN apt-get update && apt-get install -y git ca-certificates
RUN go install go.opentelemetry.io/collector/cmd/builder@v0.120.0
WORKDIR /app
COPY builder-config.yaml .
RUN builder --config builder-config.yaml

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/dist/otelcol-custom /otelcol-custom
EXPOSE 4317 4318
ENTRYPOINT ["/otelcol-custom"]
