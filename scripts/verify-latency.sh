#!/bin/bash
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

set -e

echo "Searching for a slow trace (>100ms) from trace-generator logs that occurred at least 6 seconds ago..."

# 1. 少なくとも6秒以上前のSlow trace IDを取得
# --timestamps を使ってRFC3339の時刻を取得し、現在時刻と比較する
NOW=$(date +%s)
THRESHOLD=6

# ログをパースして条件に合う最新のものを探す
TRACE_ID=$(kubectl logs -l app=trace-generator --timestamps | grep "Generated slow trace" | tac | while read -r line; do
  # line format: 2026-02-15T09:12:17.123456789Z 2026/02/15 09:12:17 Generated slow trace (>100ms): <ID>
  TS=$(echo "$line" | awk '{print $1}')
  TS_SEC=$(date -d "$TS" +%s)
  DIFF=$((NOW - TS_SEC))
  
  if [ "$DIFF" -ge "$THRESHOLD" ]; then
    echo "$line" | awk '{print $NF}'
    break
  fi
done)

if [ -z "$TRACE_ID" ]; then
  echo "Error: No slow traces found in generator logs that are old enough."
  echo "Latest logs from generator:"
  kubectl logs -l app=trace-generator --tail=5
  exit 1
fi

echo "Found slow TraceID: $TRACE_ID"
echo "Generator side Span IDs:"
# 生成器側のログから該当TraceIDの全スパンIDを抽出
kubectl logs -l app=trace-generator | grep "\[GEN\] TraceID: $TRACE_ID" | sed 's/.*SpanID: \([^,]*\).*/  - \1/' | sort -u

echo "--------------------------------------------------"
echo "Verifying that all spans for this TraceID are routed to the same Tier 2 collector pod..."

# 2. Tier 2 podsを巡回して検索 (リトライ付き)
MAX_RETRIES=3
RETRY_COUNT=0
SPANS_FOUND=0
UNIQUE_PODS=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ $SPANS_FOUND -eq 0 ]; do
  if [ $RETRY_COUNT -gt 0 ]; then
    echo "Wait 5s for decision_wait and retry... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
  fi

  for pod in $(kubectl get pods -l app=otel-tier2 -o name); do
    echo -n "Checking $pod... "
    # 該当TraceIDを含む行の直後数行からIDを抽出する
    POD_LOGS=$(kubectl logs $pod --since=2m)
    # Trace IDの行を見つけ、その後の ID : の行を抽出
    SPANS=$(echo "$POD_LOGS" | grep -A 3 "Trace ID.*: $TRACE_ID" | grep "ID.*:" | awk '{print $NF}' | sort -u)
    
    COUNT=$(echo "$SPANS" | grep -v "^$" | wc -l || echo 0)
    
    if [ $COUNT -gt 0 ]; then
      echo "FOUND $COUNT span(s)!"
      echo "Span IDs found in $pod:"
      echo "$SPANS" | sed 's/^/  - /'
      
      SPANS_FOUND=$((SPANS_FOUND + COUNT))
      UNIQUE_PODS=$(echo -e "${UNIQUE_PODS}\n${pod}" | grep -v "^$" | sort -u)
    else
      echo "Not here."
    fi
  done
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

echo "--------------------------------------------------"
POD_COUNT=$(echo "$UNIQUE_PODS" | grep -v "^$" | wc -l || echo 0)

if [ $SPANS_FOUND -gt 0 ]; then
  echo "Summary:"
  echo "- Total spans found: $SPANS_FOUND"
  echo "- Unique pods found: $POD_COUNT"
  echo "- Pods list:"
  echo "$UNIQUE_PODS" | sed 's/^/  / '

  if [ $POD_COUNT -eq 1 ]; then
    echo "--------------------------------------------------"
    echo "✅ Success: All $SPANS_FOUND spans for $TRACE_ID were found in a SINGLE pod ($UNIQUE_PODS)."
    echo "This confirms the sticky routing/load balancing is working correctly."
  else
    echo "--------------------------------------------------"
    echo "❌ Failure: Spans for $TRACE_ID were found in $POD_COUNT different pods."
    echo "This indicates that trace aggregation is NOT working as expected."
    exit 1
  fi
else
  echo "--------------------------------------------------"
  echo "❌ Failure: No spans for $TRACE_ID were found in any Tier 2 pod."
  echo "Suggestions:"
  echo "1. Check Tier 1 export errors: kubectl logs -l app=otel-tier1 | grep -i error"
  echo "2. Check Tier 2 receiver status: kubectl logs -l app=otel-tier2 | grep otlp"
  exit 1
fi
