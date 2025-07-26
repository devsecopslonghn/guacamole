{{/*
Find an env value from .Values.guacamole.extraEnv by name
Usage:
  {{ include "guacamole.envValue" (dict "name" "OPENID_ISSUER" "ctx" .) }}
*/}}
{{- define "guacamole.envValue" -}}
{{- $target := .name -}}
{{- range .ctx.Values.guacamole.extraEnv }}
  {{- if and (hasKey . "name") (eq .name $target) (hasKey . "value") }}
    {{- .value }}
  {{- end }}
{{- end }}
{{- end }}
