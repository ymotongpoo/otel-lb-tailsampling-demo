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

# 現在時刻の取得
NOW=$(date +%s)
THRESHOLD=6

echo "Searching for the latest slow trace (>100ms) from trace-generator logs..."

# 1. ログから最新のSlow trace IDを取得
# 時刻に関係なく、最新の該当ログを1行取得する。grep でエスケープの差異を避けるため単純化
LOG_DATA=$(kubectl logs -l app=trace-generator --timestamps --since=5m | grep -i "slow-span" | tail -n 1)

if [ -z "$LOG_DATA" ]; then
  echo "Error: No slow traces found in generator logs in the last 5 minutes."
  echo "Latest generator logs for reference:"
  kubectl logs -l app=trace-generator --tail=10
  exit 1
fi

# タイムスタンプの取得 (RFC3339 format from --timestamps)
TS_RAW=$(echo "$LOG_DATA" | awk '{print $1}')
TS=$(echo "$TS_RAW" | sed 's/\..*Z/Z/')

# TraceIDの抽出
if echo "$LOG_DATA" | grep -q "TraceID:"; then
  TRACE_ID=$(echo "$LOG_DATA" | sed 's/.*TraceID: \([^,]*\).*/\1/')
else
  # 旧形式: Generated slow trace (>100ms): <ID>
  TRACE_ID=$(echo "$LOG_DATA" | awk '{print $NF}')
fi

echo "Found latest slow TraceID: $TRACE_ID"
echo "Log time: $TS_RAW"

# decision_wait 分を待つ。
# クロックがズレている可能性があるため、複雑な計算はせず、
# 現在時刻とログ時刻の差が 6秒未満（またはログが未来）なら、必要な分だけスリープする。
NOW=$(date +%s)
if [[ "$OSTYPE" == "darwin"* ]]; then
  TS_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$TS" +%s 2>/dev/null || echo 0)
else
  TS_SEC=$(date -d "$TS" +%s 2>/dev/null || echo 0)
fi

DIFF=$((NOW - TS_SEC))
WAIT_TIME=$((THRESHOLD - DIFF))

if [ "$WAIT_TIME" -gt 0 ]; then
  echo "The trace is recent (or clock skew detected). Waiting ${WAIT_TIME}s for decision_wait..."
  sleep "$WAIT_TIME"
fi

echo "Generator side Span IDs for $TRACE_ID:"
# 生成器側のログから該当TraceIDの全スパンIDを抽出
kubectl logs -l app=trace-generator --since=5m | grep "TraceID: $TRACE_ID" | grep "SpanID:" | sed 's/.*SpanID: \([^,]*\).*/  - \1/' | sort -u

echo "--------------------------------------------------"
echo "Verifying Tier 2 collector logs for this TraceID..."

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
    POD_LOGS=$(kubectl logs $pod --since=5m)
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
  echo "- Total collector-side spans found: $SPANS_FOUND"
  echo "- Unique pods involved: $POD_COUNT"
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
  echo "Suggestions: Check Tier 1/Tier 2 logs for errors."
  exit 1
fi
