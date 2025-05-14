{{/*
Expand the name of the chart.
*/}}
{{- define "akash-provider-paladin.name" -}}
akash-provider-paladin
{{- end -}}

{{/*
Create a fully qualified name.
*/}}
{{- define "akash-provider-paladin.fullname" -}}
{{ include "akash-provider-paladin.name" . }}
{{- end -}}
