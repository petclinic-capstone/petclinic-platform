{{/*
=============================================================================
_helpers.tpl — shared template helpers for petclinic-service chart
=============================================================================
*/}}

{{/*
Resolve the canonical service name.
Preference order: .Values.service.name → .Chart.Name
Truncated to 63 chars (Kubernetes label limit).
*/}}
{{- define "petclinic-service.fullname" -}}
{{- if .Values.service.name }}
{{- .Values.service.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Chart label: name-version (+ → _)
*/}}
{{- define "petclinic-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels — used in matchLabels and Service selector.
Stable: never change these after first deploy without a blue/green strategy.
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels — applied to every resource.
*/}}
{{- define "petclinic-service.labels" -}}
helm.sh/chart: {{ include "petclinic-service.chart" . }}
{{ include "petclinic-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: petclinic
{{- end }}

{{/*
ServiceAccount name.
If serviceAccount.create is true: use serviceAccount.name || fullname.
If serviceAccount.create is false: use serviceAccount.name || "default".
*/}}
{{- define "petclinic-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "petclinic-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
