{{/*
Helpers for ohmRouting, in the same format as the osm-seed chart.
They are copies, not includes of "osm-seed.*": from this chart those helpers read
the parent values, where storageProvider and environment are not set.
*/}}

{{/* Labels. Usage: {{- include "routing.labels" (dict "root" . "component" "routing-server") | nindent 4 }} */}}
{{- define "routing.labels" -}}
app: ohm-routing
component: {{ .component }}
environment: {{ index .root.Values "osm-seed" "environment" }}
release: {{ .root.Release.Name }}
{{- end -}}

{{/* Selector labels. Usage: {{- include "routing.selector" (dict "root" . "component" "routing-server") | nindent 6 }} */}}
{{- define "routing.selector" -}}
app: ohm-routing
release: {{ .root.Release.Name }}
run: {{ .root.Release.Name }}-{{ .component }}
{{- end -}}

{{- define "routing.image" -}}
"{{ .Values.ohmRouting.image.name }}:{{ .Values.ohmRouting.image.tag }}"
{{- end -}}

{{- define "routing.priorityClass" -}}
{{- with .Values.ohmRouting.priorityClass }}
priorityClassName: {{ $.Release.Name }}-{{ . }}
{{- end }}
{{- end -}}

{{/* Same as osm-seed.resources. Usage: {{- include "routing.resources" .Values.ohmRouting.server | nindent 10 }} */}}
{{- define "routing.resources" -}}
{{- with .resources }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Same as osm-seed.nodeSelector */}}
{{- define "routing.nodeSelector" -}}
{{- with .nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Same as osm-seed.nodeAffinity. With staticHostPath the folder lives on one node,
so the server and the update job must both use this, and the label must
match one node only.
*/}}
{{- define "routing.nodeAffinity" -}}
{{- $v := .nodeAffinity | default dict -}}
{{- if $v.enabled }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: {{ $v.key }}
              operator: In
              values:
              {{- range $v.values }}
                - {{ . | quote }}
              {{- end }}
{{- end }}
{{- end -}}

{{/* Pod scheduling shared by all routing pods */}}
{{- define "routing.scheduling" -}}
{{- include "routing.priorityClass" . }}
{{- include "routing.nodeSelector" .Values.ohmRouting }}
{{- include "routing.nodeAffinity" .Values.ohmRouting }}
{{- end -}}

{{/* Volume with the planet and the graphs, shared by the server and the update job */}}
{{- define "routing.dataVolume" -}}
- name: routing-data
  persistentVolumeClaim:
    claimName: {{ .Release.Name }}-routing-data
{{- end -}}
