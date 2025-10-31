{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "trader.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "trader.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Database helper templates - support both internal subcharts and external databases
*/}}

{{/*
Get database host - uses subchart if internal, otherwise external config
*/}}
{{- define "stocktrader.database.host" -}}
{{- if eq .Values.database.type "internal" -}}
{{- if eq .Values.database.kind "PostgreSQL" -}}
{{- printf "%s-postgresql" .Release.Name -}}
{{- else if eq .Values.database.kind "MongoDB" -}}
{{- printf "%s-mongodb" .Release.Name -}}
{{- else -}}
{{- printf "%s-postgresql" .Release.Name -}}
{{- end -}}
{{- else -}}
{{- .Values.database.external.host -}}
{{- end -}}
{{- end -}}

{{/*
Get database port - uses subchart defaults if internal, otherwise external config
*/}}
{{- define "stocktrader.database.port" -}}
{{- if eq .Values.database.type "internal" -}}
{{- if eq .Values.database.kind "PostgreSQL" -}}
{{- .Values.postgresql.primary.service.ports.postgresql | default 5432 -}}
{{- else if eq .Values.database.kind "MongoDB" -}}
{{- .Values.mongodb.service.ports.mongodb | default 27017 -}}
{{- else -}}
{{- .Values.postgresql.primary.service.ports.postgresql | default 5432 -}}
{{- end -}}
{{- else -}}
{{- .Values.database.external.port -}}
{{- end -}}
{{- end -}}

{{/*
Get database name - uses subchart config if internal, otherwise external config
*/}}
{{- define "stocktrader.database.name" -}}
{{- if eq .Values.database.type "internal" -}}
{{- if eq .Values.database.kind "PostgreSQL" -}}
{{- .Values.postgresql.auth.database | default "trader" -}}
{{- else if eq .Values.database.kind "MongoDB" -}}
{{- .Values.mongodb.auth.database | default "trader" -}}
{{- else -}}
{{- .Values.postgresql.auth.database | default "trader" -}}
{{- end -}}
{{- else -}}
{{- .Values.database.external.db -}}
{{- end -}}
{{- end -}}

{{/*
Get database username - uses subchart config if internal, otherwise external config
*/}}
{{- define "stocktrader.database.username" -}}
{{- if eq .Values.database.type "internal" -}}
{{- if eq .Values.database.kind "PostgreSQL" -}}
{{- .Values.postgresql.auth.username | default "stocktrader" -}}
{{- else if eq .Values.database.kind "MongoDB" -}}
{{- .Values.mongodb.auth.username | default "stocktrader" -}}
{{- else -}}
{{- .Values.postgresql.auth.username | default "stocktrader" -}}
{{- end -}}
{{- else -}}
{{- .Values.database.external.id -}}
{{- end -}}
{{- end -}}

{{/*
Get database password - uses subchart config if internal, otherwise external config
*/}}
{{- define "stocktrader.database.password" -}}
{{- if eq .Values.database.type "internal" -}}
{{- if eq .Values.database.kind "PostgreSQL" -}}
{{- .Values.postgresql.auth.password | default "changeme" -}}
{{- else if eq .Values.database.kind "MongoDB" -}}
{{- .Values.mongodb.auth.password | default "changeme" -}}
{{- else -}}
{{- .Values.postgresql.auth.password | default "changeme" -}}
{{- end -}}
{{- else -}}
{{- .Values.database.external.password -}}
{{- end -}}
{{- end -}}

{{/*
Get database SSL setting - uses subchart defaults if internal, otherwise external config
*/}}
{{- define "stocktrader.database.ssl" -}}
{{- if eq .Values.database.type "internal" -}}
{{- "false" -}}
{{- else -}}
{{- .Values.database.external.ssl -}}
{{- end -}}
{{- end -}}

{{/*
Redis helper templates
*/}}

{{/*
Get Redis URL - uses internal subchart if type is internal, otherwise external config
*/}}
{{- define "stocktrader.redis.url" -}}
{{- if eq .Values.redis.type "internal" -}}
{{- if .Values.redis.auth.enabled -}}
{{- printf "redis://:%s@%s-redis-master:6379" .Values.redis.auth.password .Release.Name -}}
{{- else -}}
{{- printf "redis://%s-redis-master:6379" .Release.Name -}}
{{- end -}}
{{- else -}}
{{- if .Values.redis.external.urlWithCredentials -}}
{{- .Values.redis.external.urlWithCredentials -}}
{{- else if .Values.redis.external.password -}}
{{- printf "redis://:%s@%s:%d/%d" .Values.redis.external.password .Values.redis.external.host (.Values.redis.external.port | default 6379) (.Values.redis.external.database | default 0) -}}
{{- else -}}
{{- printf "redis://%s:%d/%d" .Values.redis.external.host (.Values.redis.external.port | default 6379) (.Values.redis.external.database | default 0) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Check if Redis is enabled - true if type is internal and enabled is true, or type is external and external.enabled is true
*/}}
{{- define "stocktrader.redis.enabled" -}}
{{- if eq .Values.redis.type "internal" -}}
{{- .Values.redis.enabled -}}
{{- else -}}
{{- .Values.redis.external.enabled -}}
{{- end -}}
{{- end -}}

{{/*
MongoDB helper templates
*/}}

{{/*
Get MongoDB connection string - uses subchart if enabled, otherwise external config
*/}}
{{- define "stocktrader.mongodb.connectionString" -}}
{{- if .Values.mongodb.enabled -}}
{{- if .Values.mongodb.auth.enabled -}}
{{- printf "mongodb://%s:%s@%s-mongodb:27017/%s?authSource=%s" .Values.mongodb.auth.username .Values.mongodb.auth.password .Release.Name .Values.mongodb.auth.database .Values.mongodb.auth.database -}}
{{- else -}}
{{- printf "mongodb://%s-mongodb:27017/%s" .Release.Name .Values.mongodb.auth.database -}}
{{- end -}}
{{- else -}}
{{- .Values.mongo.connectionString -}}
{{- end -}}
{{- end -}}

{{/*
Get MongoDB host
*/}}
{{- define "stocktrader.mongodb.host" -}}
{{- if .Values.mongodb.enabled -}}
{{- printf "%s-mongodb" .Release.Name -}}
{{- else -}}
{{- .Values.mongo.ip -}}
{{- end -}}
{{- end -}}

{{/*
Kafka helper templates
*/}}

{{/*
Get Kafka bootstrap address - uses subchart if enabled, otherwise external config
*/}}
{{- define "stocktrader.kafka.address" -}}
{{- if .Values.kafka.enabled -}}
{{- printf "%s-kafka:9092" .Release.Name -}}
{{- else -}}
{{- .Values.kafka.address -}}
{{- end -}}
{{- end -}}
