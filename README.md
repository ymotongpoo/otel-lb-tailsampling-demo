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

### 同一トレースの集約確認

ロードバランサー・エクスポーターが正しく動作している（同じ TraceID のスパンが同じ Tier 2 インスタンスに飛んでいる）ことを確認するには、以下の手順を行います。

1. **TraceID の取得**:
   `trace-generator` のログから、生成された TraceID を一つコピーします。
   ```bash
   kubectl logs -l app=trace-generator | grep "Generated trace" | tail -n 1
   ```

2. **Tier 2 での検索**:
   取得した TraceID が、**特定の pod 1つだけに現れること**を確認します。
   ```bash
   # 全ての Tier 2 pod に対して grep を実行
   for pod in $(kubectl get pods -l app=otel-tier2 -o name); do
     echo "Checking $pod..."
     kubectl logs $pod | grep <コピーしたTraceID>
   done
   ```

もし設定が正しくなければ、同じ TraceID のスパン（root-span と child-span など）が別々の pod のログに分散して現れます。正しく設定されていれば、必ず特定の pod 1つのログにのみ集約されます。

### トレースが見つからない場合のトラブルシューティング

1. **テイルサンプリングによるドロップ**:
   現在の設定では以下のいずれかに該当するトレースのみが保持されます：
   - ステータスが `ERROR` のスパンを含む
   - レイテンシー（実行時間）が `100ms` を超えるスパンを含む
   - 上記以外でランダムにサンプリングされた 10%

   検証のために、`app/main.go` ではランダムに 150ms の遅延を持つスパンを生成するようにしています。

2. **決定待ち時間**:
   `tail_sampling` の `decision_wait: 5s` により、最初のスパンが届いてからログに出力されるまで少なくとも5秒かかります。少し待ってから再度確認してください。

3. **Tier 1 の状況確認**:
   Tier 1 がそもそも Tier 2 に送信できているかを確認します。Tier 1 のログに `Exporting failed` などのエラーが出ていないか確認してください。
   ```bash
   kubectl logs -l app=otel-tier1
   ```
