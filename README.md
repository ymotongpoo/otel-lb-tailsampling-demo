# OpenTelemetry Collector PoC: Load Balancer & Tail Sampling

このリポジトリは、OpenTelemetry Collectorの2層構成（Tier 1 & Tier 2）におけるロードバランサー・エクスポーターとテイルサンプリング・プロセッサーの動作を確認するためのPoC環境です。

## 概要

このプロジェクトでは以下の構成を検証します。

1. **Trace Generator (app)**: OTLPでトレースデータを生成して Tier 1 に送信します。
2. **Tier 1 Collector (Gateway)**: `loadbalancing` エクスポーターを使用し、トレースIDに基づいて特定の Tier 2 インスタンスにスパンをルーティングします。これにより、同じトレースに属するすべてのスパンが同一の Tier 2 インスタンスに集約されます。
3. **Tier 2 Collector (Sampling)**: `tail_sampling` プロセッサーを使用し、トレース全体が揃った状態でサンプリングの決定（例：エラーが含まれるトレースのみ保存する等）を行います。

## プロジェクト構成

- `app/`: トレース生成器（Go製）のソースコードとDockerfile
- `otelcol/`: カスタムOpenTelemetry Collectorのビルド設定
  - `builder-config.yaml`: OCB (OpenTelemetry Collector Builder) 用の設定ファイル
  - `Dockerfile`: Debian-slimをベースとしたマルチステージビルド設定
- `manifests/`: Kubernetes用のマニフェストファイル群
- `skaffold.yaml`: Skaffoldの設定ファイル

## 必要条件

- Docker
- Kubernetes クラスター (k3d, minikube等)
- [Skaffold](https://skaffold.dev/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## クイックスタート

### 1. クラスターの準備

#### k3d を使用する場合

ローカルレジストリ付きのk3dクラスターを作成することを推奨します。

```bash
k3d cluster create otel-poc --registry-create otel-poc-registry:5000
```

#### minikube を使用する場合

minikubeを使用する場合は、以下のコマンドで起動します。

```bash
minikube start
```

Skaffoldが自動的にminikubeを認識し、イメージをminikube内のDockerデーモンでビルドするため、レジストリへのプッシュは不要です。

### 2. 環境の構築と起動

Skaffoldを使用して、コレクターとアプリのビルド、およびデプロイを一括で実行します。

```bash
# 1回限りの実行の場合
skaffold run

# 開発モード（自動再ビルド有効）の場合
skaffold dev
```

## 動作確認

デプロイ完了後、以下のコマンドでログを確認し、期待通りに動作しているか検証します。

### Tier 1 のログ確認
Tier 1 が受信したスパンを Tier 2 に振り分けていることを確認します。

```bash
kubectl logs -l app=otel-tier1
```

### Tier 2 のログ確認
Tier 2 でテイルサンプリングが行われ、`debug` エクスポーター（詳細ログ）からスパンが出力されていることを確認します。

```bash
kubectl logs -l app=otel-tier2
```
