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

# OpenTelemetry Collector PoC Demo Recording Script

# === Output Settings ===
Output demo.mp4

# === Terminal Settings ===
Set Shell zsh
Set FontSize 18
Set Width 1600
Set Height 900
Set WindowBar Colorful
Set BorderRadius 10
Set Framerate 30
Set Theme "nord"
Set TypingSpeed 50ms

# ============================================================
# Step 0: アーキテクチャ説明
# ============================================================
Type `echo ""`
Enter
Type `echo "========================================"`
Enter
Type `echo "  OpenTelemetry Collector PoC Demo"`
Enter
Type `echo "  Load Balancer + Tail Sampling"`
Enter
Type `echo "========================================"`
Enter
Type `echo ""`
Enter
Type `echo "  Trace Generator (App)"`
Enter
Type `echo "        │"`
Enter
Type `echo "        ▼"`
Enter
Type `echo "  ┌──────────────┐"`
Enter
Type `echo "  │   Tier 1     │  loadbalancing exporter"`
Enter
Type `echo "  │   (Gateway)  │  → TraceID でルーティング"`
Enter
Type `echo "  └──┬───────┬───┘"`
Enter
Type `echo "     │       │"`
Enter
Type `echo "     ▼       ▼"`
Enter
Type `echo "  ┌──────┐ ┌──────┐"`
Enter
Type `echo "  │Tier2a│ │Tier2b│  tail_sampling processor"`
Enter
Type `echo "  └──────┘ └──────┘"`
Enter
Type `echo ""`
Enter
Type `echo "目的: 同じ TraceID のスパンが"`
Enter
Type `echo "      同一の Tier 2 Collector に集約されることを確認"`
Enter
Type `echo ""`
Enter
Sleep 8s

# ============================================================
# Step 1: Pod 状況確認
# ============================================================
Type `echo "========================================"`
Enter
Type `echo "  Step 1: Pod 状況確認"`
Enter
Type `echo "========================================"`
Enter
Sleep 1s

Type "kubectl get pods"
Enter
Sleep 5s

# ============================================================
# Step 2: スロートレース検出
# ============================================================
Type `echo ""`
Enter
Type `echo "========================================"`
Enter
Type `echo "  Step 2: スロートレースの検出"`
Enter
Type `echo "========================================"`
Enter
Type `echo "trace-generator のログから 100ms 超のスロートレースを検索します"`
Enter
Sleep 2s

Type `kubectl logs -l app=trace-generator --since=10m | grep -i 'slow-span' | tail -n 5`
Enter
Sleep 5s

# --- Hide: TraceID を変数に格納 ---
Hide
Type `TRACE_ID=$(kubectl logs -l app=trace-generator --since=10m | grep -i 'slow-span' | tail -n 1 | sed 's/.*TraceID: \([^,]*\).*/\1/' | tr -d '\r' | xargs)`
Enter
Sleep 2s
Show

Type `echo ""`
Enter
Type `echo ">>> 検出したスロー TraceID: $TRACE_ID"`
Enter
Sleep 4s

# ============================================================
# Step 3: アプリ側スパンID一覧
# ============================================================
Type `echo ""`
Enter
Type `echo "========================================"`
Enter
Type `echo "  Step 3: アプリ側スパンID一覧"`
Enter
Type `echo "========================================"`
Enter
Type `echo "上記 TraceID に紐づく全スパンを表示します"`
Enter
Sleep 2s

Type `kubectl logs -l app=trace-generator --since=10m | grep "$TRACE_ID" | grep 'SpanID:' | sed -E 's/.*SpanID: ([0-9a-f]+), Name: ([^)]*).*/  - \1 (\2)/'`
Enter
Sleep 5s

# --- Hide: decision_wait を待機 ---
Hide
Sleep 6s
Show

# ============================================================
# Step 4: Tier 2 集約検証
# ============================================================
Type `echo ""`
Enter
Type `echo "========================================"`
Enter
Type `echo "  Step 4: Tier 2 集約検証"`
Enter
Type `echo "========================================"`
Enter
Type `echo "各 Tier 2 Pod を検索し、スパンの集約状況を確認します"`
Enter
Sleep 2s

Type `for pod in $(kubectl get pods -l app=otel-tier2 -o name); do echo ""; echo "--- Checking $pod ---"; SPANS=$(kubectl logs $pod --since=15m | grep -A 5 "Trace ID.*: $TRACE_ID" | grep "ID.*:" | grep -vE "Trace ID|Parent ID" | awk "{print \$NF}" | grep -v ":" | sort -u); COUNT=$(echo "$SPANS" | grep -v "^$" | wc -l); if [ $COUNT -gt 0 ]; then echo "  ✅ FOUND $COUNT span(s):"; echo "$SPANS" | sed "s/^/    - /"; else echo "  (not found)"; fi; done`
Enter
Sleep 8s

# --- Hide: 結果の集計 ---
Hide
Type `RESULT_PODS=""; for pod in $(kubectl get pods -l app=otel-tier2 -o name); do COUNT=$(kubectl logs $pod --since=15m | grep -A 5 "Trace ID.*: $TRACE_ID" | grep "ID.*:" | grep -vE "Trace ID|Parent ID" | awk "{print \$NF}" | grep -v ":" | sort -u | grep -v "^$" | wc -l); if [ $COUNT -gt 0 ]; then RESULT_PODS="$RESULT_PODS $pod"; fi; done`
Enter
Sleep 3s
Type `POD_COUNT=$(echo $RESULT_PODS | wc -w)`
Enter
Sleep 1s
Show

# ============================================================
# 結論の表示
# ============================================================
Type `echo ""`
Enter
Type `echo "========================================"`
Enter
Type `echo "  結果"`
Enter
Type `echo "========================================"`
Enter
Sleep 1s

Type `if [ "$POD_COUNT" -eq 1 ]; then echo "✅ 成功: TraceID $TRACE_ID の全スパンが"; echo "   単一の Pod ($RESULT_PODS) に集約されました。"; echo ""; echo "   → ロードバランシング エクスポーターによる"; echo "     TraceID ベースのルーティングが正常に動作しています。"; else echo "❌ 失敗: スパンが $POD_COUNT 個の Pod に分散しています。"; fi`
Enter
Sleep 8s

# End
Type `echo ""`
Enter
Type `echo "========================================"`
Enter
Type `echo "  Demo Complete"`
Enter
Type `echo "========================================"`
Enter
Sleep 3s
