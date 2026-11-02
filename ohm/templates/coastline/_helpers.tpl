{{/*
Helpers for ohmCoastline, in the same format as the routing helpers.
*/}}

{{- define "coastline.labels" -}}
app: ohm-coastline
component: {{ .component }}
environment: {{ index .root.Values "osm-seed" "environment" }}
release: {{ .root.Release.Name }}
{{- end -}}

{{- define "coastline.image" -}}
"{{ .Values.ohmCoastline.image.name }}:{{ .Values.ohmCoastline.image.tag }}"
{{- end -}}

{{/* Pod scheduling: priorityClass, nodeSelector and nodeAffinity from ohmCoastline */}}
{{- define "coastline.scheduling" -}}
{{- $c := .Values.ohmCoastline -}}
{{- with $c.priorityClass }}
priorityClassName: {{ $.Release.Name }}-{{ . }}
{{- end }}
{{- with $c.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- $a := $c.nodeAffinity | default dict }}
{{- if $a.enabled }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: {{ $a.key }}
              operator: In
              values:
              {{- range $a.values }}
                - {{ . | quote }}
              {{- end }}
{{- end }}
{{- end -}}
