{{- define "routing.name" -}}
{{- printf "%s-routing" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "routing.labels" -}}
app.kubernetes.io/name: routing
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "routing.image" -}}
{{ .Values.ohmRouting.image.name }}:{{ .Values.ohmRouting.image.tag }}
{{- end -}}

{{- define "routing.scheduling" -}}
{{- $r := .Values.ohmRouting | default dict }}
{{- with $r.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $r.priorityClass }}
priorityClassName: {{ $.Release.Name }}-{{ . }}
{{- end }}
{{- end -}}
