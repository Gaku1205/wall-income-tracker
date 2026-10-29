#!/usr/bin/env bash
# 順番待ち（ai:queue）を1つ進める。queue.yml から呼ぶ
source "$(dirname "$0")/pipeline-lib.sh"
has_pipeline_token || { echo "PIPELINE_TOKEN が無いので何もしません"; exit 0; }
start_next_in_queue || { echo "::error::順番待ちを進められませんでした（トークンの権限を確認してください）"; exit 1; }
