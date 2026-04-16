{{/*
=============================================================
Helm Helpers: _helpers.tpl
파일 위치: helm-charts/order-system/templates/_helpers.tpl

공통 템플릿 함수 정의. 모든 템플릿에서 include로 호출한다.
=============================================================
*/}}

{{/* Chart 이름 */}}
{{- define "order-system.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* 전체 릴리즈 이름 (네임스페이스 포함) */}}
{{- define "order-system.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Chart 버전 레이블 */}}
{{- define "order-system.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* 공통 레이블 (모든 리소스에 적용) */}}
{{- define "order-system.labels" -}}
helm.sh/chart: {{ include "order-system.chart" . }}
{{ include "order-system.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: order-system
gitops.io/environment: {{ .Values.global.environment | quote }}
{{- end }}

{{/* 셀렉터 레이블 (변경되면 안 되는 레이블) */}}
{{- define "order-system.selectorLabels" -}}
app.kubernetes.io/name: {{ include "order-system.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* ServiceAccount 이름 */}}
{{- define "order-system.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "order-system.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
