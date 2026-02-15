<!--
Copyright 2026 Yoshi Yamaguchi

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

SPDX-License-Identifier: Apache-2.0
-->

# Trace Generator

このアプリケーションは、OpenTelemetry Collectorのロードバランシングとテールサンプリングの動作をテストするためのトレースデータを生成します。

## 機能

- 1秒間に1回トレースを生成します。
- 各トレースは、1つのルートスパンと3つの子スパンで構成されます。
- 5回に1回の頻度でエラーを含むスパンを生成します。

## 実行方法

### ローカルでのビルド

```bash
go build -o generator main.go
./generator
```

### Dockerイメージのビルド

```bash
docker build -t otel-poc-app:latest .
```

### 環境変数

- `OTEL_EXPORTER_OTLP_ENDPOINT`: データを送信するコレクターのエンドポイント（デフォルト: `otel-gateway:4317`）
