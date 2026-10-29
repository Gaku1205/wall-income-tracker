#!/usr/bin/env bash
# AWS App Runner に公開する：Docker のイメージを作って ECR に置き、App Runner のサービスを新しいイメージにする。
# サービスがまだ無ければ作る（最初の公開）。終わるまで待ち、公開先のURLを出す。deploy.yml から呼ぶ。
# AWS の鍵は使わない：GitHub の OIDC で、AWS_ROLE_ARN の役割を一時的に借りる（configure-aws-credentials が先に済ませる）。
#
# 環境変数：
#   CONFIG          pipeline.json の公開先の設定（JSON）。service（サービス名）、port（既定 8080）、dockerfile（既定 Dockerfile）、
#                   cpu（既定 256 = 0.25 vCPU）、memory（既定 512 MB）、health（ヘルスチェックのパス。既定は TCP）
#   ACCESS_ROLE_ARN App Runner が ECR からイメージを読むための役割（docs/pipeline.md の手順で作る）
#   SHA             公開するコミット
#   GITHUB_OUTPUT   url を書く（無ければ標準出力）
#   APPRUNNER_WAIT_SEC / APPRUNNER_WAIT_MAX  完了を待つ間隔（秒）と回数（既定 15秒×80回 = 20分）
set -euo pipefail
out="${GITHUB_OUTPUT:-/dev/stdout}"
cfg="${CONFIG:?CONFIG が要ります}"
service=$(jq -r '.service // empty' <<< "$cfg")
port=$(jq -r '.port // 8080 | tostring' <<< "$cfg")
dockerfile=$(jq -r '.dockerfile // "Dockerfile"' <<< "$cfg")
cpu=$(jq -r '.cpu // 256 | tostring' <<< "$cfg")
memory=$(jq -r '.memory // 512 | tostring' <<< "$cfg")
health=$(jq -r '.health // empty' <<< "$cfg")
sha="${SHA:?SHA が要ります}"
wait_sec="${APPRUNNER_WAIT_SEC:-15}"
wait_max="${APPRUNNER_WAIT_MAX:-80}"

[ -n "$service" ] || { echo "::error::pipeline.json の aws-apprunner に service（サービス名）が無い"; exit 1; }
[ -f "$dockerfile" ] || { echo "::error::$dockerfile が無い（App Runner はコンテナで動かすので、Dockerfile が要る）"; exit 1; }
[ -n "${ACCESS_ROLE_ARN:-}" ] || { echo "::error::Variable の AWS_APPRUNNER_ACCESS_ROLE_ARN が無い（docs/pipeline.md「AWS App Runner」の手順）"; exit 1; }

account=$(aws sts get-caller-identity --query Account --output text)
region=$(aws configure get region 2> /dev/null || true)
region="${region:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
[ -n "$region" ] || { echo "::error::AWS のリージョンが分からない（Variable の AWS_REGION）"; exit 1; }
registry="${account}.dkr.ecr.${region}.amazonaws.com"
image="${registry}/${service}:${sha}"

# イメージの置き場（ECR）が無ければ作る
if ! aws ecr describe-repositories --repository-names "$service" > /dev/null 2>&1; then
  aws ecr create-repository --repository-name "$service" --image-scanning-configuration scanOnPush=true > /dev/null
  echo "ECR に $service を作りました"
fi

echo "::group::イメージを作って置く（$image）"
aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"
docker build -t "$image" -f "$dockerfile" .
docker push "$image"
echo "::endgroup::"

source_cfg=$(jq -nc --arg image "$image" --arg port "$port" --arg role "$ACCESS_ROLE_ARN" \
  '{ImageRepository: {ImageIdentifier: $image, ImageRepositoryType: "ECR", ImageConfiguration: {Port: $port}},
    AuthenticationConfiguration: {AccessRoleArn: $role}, AutoDeploymentsEnabled: false}')

arn=$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='${service}'].ServiceArn | [0]" --output text)
if [ -z "$arn" ] || [ "$arn" = None ]; then
  instance=$(jq -nc --arg cpu "$cpu" --arg mem "$memory" '{Cpu: $cpu, Memory: $mem}')
  health_args=()
  if [ -n "$health" ]; then
    health_args=(--health-check-configuration "$(jq -nc --arg p "$health" '{Protocol: "HTTP", Path: $p}')")
  fi
  created=$(aws apprunner create-service --service-name "$service" --source-configuration "$source_cfg" \
    --instance-configuration "$instance" "${health_args[@]}" --output json)
  arn=$(jq -r '.Service.ServiceArn' <<< "$created")
  op=$(jq -r '.OperationId' <<< "$created")
  echo "App Runner のサービス $service を作りました（最初の公開）"
else
  op=$(aws apprunner update-service --service-arn "$arn" --source-configuration "$source_cfg" --query OperationId --output text)
  echo "App Runner のサービス $service を新しいイメージにします"
fi

# 終わるまで待つ（作る・差し替えるのに数分かかる）
status=""
for _ in $(seq 1 "$wait_max"); do
  status=$(aws apprunner list-operations --service-arn "$arn" --query "OperationSummaryList[?Id=='${op}'].Status | [0]" --output text)
  case "$status" in
    SUCCEEDED) break ;;
    FAILED | ROLLBACK_SUCCEEDED | ROLLBACK_FAILED | ROLLBACK_IN_PROGRESS)
      echo "::error::App Runner の公開が失敗しました（${status}）。AWS の App Runner の画面でログを見てください"
      exit 1 ;;
  esac
  sleep "$wait_sec"
done
if [ "$status" != SUCCEEDED ]; then
  echo "::error::App Runner の公開が時間内に終わりませんでした（最後の状態：${status:-不明}）"
  exit 1
fi

url=$(aws apprunner describe-service --service-arn "$arn" --query Service.ServiceUrl --output text)
echo "url=https://${url}" >> "$out"
echo "公開しました：https://${url}"
