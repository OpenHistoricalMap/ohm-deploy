{{/*
Common labels
*/}}
{{- define "ohm.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: ohm-services
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
ohm.environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Per-service labels. Pass dict with "name" key.
Usage: {{ include "ohm.serviceLabels" (dict "ctx" . "name" "taginfo") }}
*/}}
{{- define "ohm.serviceLabels" -}}
{{ include "ohm.labels" .ctx }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/component: {{ .name }}
{{- end }}

{{/*
Image string with tag fallback
Usage: {{ include "ohm.image" (dict "repo" .repo "tag" .tag "default" "latest") }}
*/}}
{{- define "ohm.image" -}}
{{- $tag := .tag | default .default -}}
{{ .repo }}:{{ $tag }}
{{- end }}

{{/*
Common pod spec defaults
*/}}
{{- define "ohm.podDefaults" -}}
restartPolicy: Always
{{- end }}
