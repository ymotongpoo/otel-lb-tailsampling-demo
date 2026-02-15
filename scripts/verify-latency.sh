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
  echo "Error: No slow traces found in generator logs. Please wait a few seconds and try again."
  exit 1
fi

echo "Found slow TraceID: $TRACE_ID"
echo "Checking Tier 2 collector logs for this TraceID (may take a few seconds for tail sampling decision wait)..."

# 2. Tier 2 podsを巡回して検索
FOUND=false
for pod in $(kubectl get pods -l app=otel-tier2 -o name); do
  echo -n "Checking $pod... "
  # grepでTraceIDを検索。見つかれば詳細を表示。
  if kubectl logs $pod | grep -q "$TRACE_ID"; then
    echo "FOUND!"
    FOUND=true
    break
  else
    echo "Not here."
  fi
done

if [ "$FOUND" = true ]; then
  echo "Success: Slow trace $TRACE_ID was correctly sampled and found in Tier 2."
else
  echo "Failure: Slow trace $TRACE_ID was NOT found in any Tier 2 pod. Check decision_wait (5s) and retry."
  exit 1
fi
