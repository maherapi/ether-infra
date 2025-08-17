{{/*
Expand the name of the chart.
*/}}
{{- define "ethereum-infrastructure.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ethereum-infrastructure.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ethereum-infrastructure.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ethereum-infrastructure.labels" -}}
helm.sh/chart: {{ include "ethereum-infrastructure.chart" . }}
{{ include "ethereum-infrastructure.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ethereum-infrastructure.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ethereum-infrastructure.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Sync node labels
*/}}
{{- define "ethereum-infrastructure.syncNodeLabels" -}}
{{ include "ethereum-infrastructure.labels" . }}
app.kubernetes.io/component: sync-node
{{- end }}

{{/*
Serve node labels
*/}}
{{- define "ethereum-infrastructure.serveNodeLabels" -}}
{{ include "ethereum-infrastructure.labels" . }}
app.kubernetes.io/component: serve-node
{{- end }}

{{/*
Snapshot job labels
*/}}
{{- define "ethereum-infrastructure.snapshotJobLabels" -}}
{{ include "ethereum-infrastructure.labels" . }}
app.kubernetes.io/component: snapshot-job
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ethereum-infrastructure.serviceAccountName" -}}
{{- if .Values.rbac.create }}
{{- default (include "ethereum-infrastructure.fullname" .) .Values.rbac.serviceAccountName }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccountName }}
{{- end }}
{{- end }}

{{/*
Generate image name with registry and tag
*/}}
{{- define "ethereum-infrastructure.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repository := .repository -}}
{{- $tag := .tag | default "latest" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end }}

{{/*
Generate storage class name
*/}}
{{- define "ethereum-infrastructure.storageClass" -}}
{{- if .storageClass -}}
{{- .storageClass -}}
{{- else -}}
{{- .Values.global.storageClass -}}
{{- end -}}
{{- end }}

{{/*
Generate sync node statefulset name for specific client
*/}}
{{- define "ethereum-infrastructure.syncNodeName" -}}
{{- printf "%s-sync-%s" (include "ethereum-infrastructure.fullname" .) . -}}
{{- end }}

{{/*
Generate serve node deployment name
*/}}
{{- define "ethereum-infrastructure.serveNodeName" -}}
{{- printf "%s-serve" (include "ethereum-infrastructure.fullname" .) -}}
{{- end }}

{{/*
Generate snapshot job name
*/}}
{{- define "ethereum-infrastructure.snapshotJobName" -}}
{{- printf "%s-snapshot" (include "ethereum-infrastructure.fullname" .) -}}
{{- end }}

{{/*
Generate client-specific configuration
*/}}
{{- define "ethereum-infrastructure.clientConfig" -}}
{{- $client := . -}}
{{- $config := dict -}}
{{- if eq $client "geth" -}}
{{- $_ := set $config "ports" (dict "rpc" 8545 "ws" 8546 "metrics" 6060) -}}
{{- $_ := set $config "healthPath" "/health" -}}
{{- else if eq $client "nethermind" -}}
{{- $_ := set $config "ports" (dict "rpc" 8545 "ws" 8546 "metrics" 6060) -}}
{{- $_ := set $config "healthPath" "/health" -}}
{{- else if eq $client "erigon" -}}
{{- $_ := set $config "ports" (dict "rpc" 8545 "ws" 8546 "metrics" 6060) -}}
{{- $_ := set $config "healthPath" "/health" -}}
{{- else if eq $client "besu" -}}
{{- $_ := set $config "ports" (dict "rpc" 8545 "ws" 8546 "metrics" 9545) -}}
{{- $_ := set $config "healthPath" "/health" -}}
{{- end -}}
{{- $config | toYaml -}}
{{- end }}

{{/*
Generate network bootnodes
*/}}
{{- define "ethereum-infrastructure.bootnodes" -}}
{{- $network := .Values.ethereum.network -}}
{{- $bootnodes := index .Values.ethereum.bootnodes $network -}}
{{- if $bootnodes -}}
{{- join "," $bootnodes -}}
{{- end -}}
{{- end }}

{{/*
Generate security context
*/}}
{{- define "ethereum-infrastructure.securityContext" -}}
{{- with .Values.global.securityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate pod security context
*/}}
{{- define "ethereum-infrastructure.podSecurityContext" -}}
{{- with .Values.global.securityContext }}
securityContext:
  runAsNonRoot: {{ .runAsNonRoot | default true }}
  runAsUser: {{ .runAsUser | default 1000 }}
  runAsGroup: {{ .runAsGroup | default 1000 }}
  fsGroup: {{ .fsGroup | default 1000 }}
{{- end }}
{{- end }}

{{/*
Generate resource requirements
*/}}
{{- define "ethereum-infrastructure.resources" -}}
{{- if . }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate node selector
*/}}
{{- define "ethereum-infrastructure.nodeSelector" -}}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate tolerations
*/}}
{{- define "ethereum-infrastructure.tolerations" -}}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate affinity
*/}}
{{- define "ethereum-infrastructure.affinity" -}}
{{- if .Values.affinity }}
affinity:
  {{- toYaml .Values.affinity | nindent 2 }}
{{- else if .antiAffinity.enabled }}
affinity:
  podAntiAffinity:
    {{- if eq .antiAffinity.type "required" }}
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: {{ include "ethereum-infrastructure.name" $ }}
          app.kubernetes.io/instance: {{ $.Release.Name }}
          app.kubernetes.io/component: {{ .component }}
      topologyKey: kubernetes.io/hostname
    {{- else }}
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: {{ include "ethereum-infrastructure.name" $ }}
            app.kubernetes.io/instance: {{ $.Release.Name }}
            app.kubernetes.io/component: {{ .component }}
        topologyKey: kubernetes.io/hostname
    {{- end }}
{{- end }}
{{- end }}
