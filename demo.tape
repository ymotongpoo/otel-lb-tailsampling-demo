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
# loadbalancing exporter + tail_sampling processor の動作検証

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
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

# ============================================================
# Step 1: Pod の状態を確認
# ============================================================
Sleep 1s
Type "kubectl get pods"
Enter
Sleep 5s

# ============================================================
# Step 2: trace-generator のログからスロートレースを探す
# ============================================================
Type `kubectl logs -l app=trace-generator --since=10m | grep "slow-span" | tail -5`
Enter
Sleep 5s

# ============================================================
# Step 3: 最新のスロートレースの TraceID を取得
# ============================================================
Type `TRACE_ID=$(kubectl logs -l app=trace-generator --since=10m | grep "slow-span" | tail -1 | sed 's/.*TraceID: \([^,]*\).*/\1/' | tr -d '\r' | xargs)`
Enter
Sleep 2s

Type "echo $TRACE_ID"
Enter
Sleep 3s

# ============================================================
# Step 4: この TraceID に紐づくスパン一覧を確認
# ============================================================
Type `kubectl logs -l app=trace-generator --since=10m | grep "$TRACE_ID" | grep "SpanID:" | sed -E 's/.*SpanID: ([0-9a-f]+), Name: ([^)]*).*/  \1  \2/'`
Enter
Sleep 5s

# ============================================================
# decision_wait (5s) を待つ — 裏で sleep して画面には見せない
# ============================================================
Hide
Type "sleep 6"
Enter
Sleep 7s
Show

# ============================================================
# Step 5: Tier 2 の各 Pod でスパンの集約状況を確認
# ============================================================
Type `for pod in $(kubectl get pods -l app=otel-tier2 -o name); do`
Enter
Sleep 300ms
Type `  echo "--- $pod ---"`
Enter
Sleep 300ms
Type `  SPANS=$(kubectl logs $pod --since=15m | grep -A5 "Trace ID.*: $TRACE_ID" | grep "ID.*:" | grep -vE "Trace ID|Parent ID" | awk '{print $NF}' | grep -v ":" | sort -u)`
Enter
Sleep 300ms
Type `  COUNT=$(echo "$SPANS" | grep -v "^$" | wc -l | tr -d ' ')`
Enter
Sleep 300ms
Type `  if [ "$COUNT" -gt 0 ]; then echo "  ✅ $COUNT span(s) found"; echo "$SPANS" | sed 's/^/    /'; else echo "  (none)"; fi`
Enter
Sleep 300ms
Type "done"
Enter
Sleep 10s

# ============================================================
# Step 6: 結果の判定 — 全スパンが単一 Pod に集約されたか
# ============================================================

# 裏で集計用の変数を準備
Hide
Type `RESULT_PODS=""`
Enter
Sleep 500ms
Type `for pod in $(kubectl get pods -l app=otel-tier2 -o name); do COUNT=$(kubectl logs $pod --since=15m | grep -A5 "Trace ID.*: $TRACE_ID" | grep "ID.*:" | grep -vE "Trace ID|Parent ID" | awk '{print $NF}' | grep -v ":" | sort -u | grep -v "^$" | wc -l); if [ $COUNT -gt 0 ]; then RESULT_PODS="$RESULT_PODS $pod"; fi; done`
Enter
Sleep 3s
Type `POD_COUNT=$(echo $RESULT_PODS | wc -w | tr -d ' ')`
Enter
Sleep 1s
Show

Type `if [ "$POD_COUNT" -eq 1 ]; then echo "✅ 成功: TraceID $TRACE_ID の全スパンが単一 Pod に集約されました"; echo "   Pod: $RESULT_PODS"; echo "   → loadbalancing exporter による TraceID ベースルーティングが正常動作"; else echo "❌ 失敗: スパンが ${POD_COUNT} 個の Pod に分散しています"; fi`
Enter
Sleep 8s

Sleep 3s
