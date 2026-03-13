# StockTrader CR Configuration Reference

The `StockTrader` custom resource controls every aspect of the deployed application. All fields map directly to Helm values in `operator/helm-charts/stocktrader/`. This document describes each section.

The full annotated sample is at [`operator/config/samples/operators_v1_stocktrader.yaml`](../operator/config/samples/operators_v1_stocktrader.yaml).

---

## `spec.global`

Top-level settings affecting the entire deployment.

| Field | Type | Default | Description |
|---|---|---|---|
| `auth` | string | `basic` | Authentication mode. One of: `basic`, `oidc`, `ldap`, `saml` |
| `secretName` | string | `{{ .Release.Name }}-credentials` | Name of the Kubernetes `Secret` containing connection credentials |
| `externalSecret` | bool | `false` | Set `true` when using ESO to manage the credentials secret |
| `externalConfigMap` | bool | `false` | Set `true` if the config map is managed externally |
| `configMapName` | string | `{{ .Release.Name }}-config` | Name of the application config map |
| `ingress` | bool | `false` | Enable Kubernetes `Ingress` resource for external access |
| `route` | bool | `false` | Enable OpenShift `Route` resource (OpenShift only) |
| `istio` | bool | `false` | Enable Istio sidecar injection and `Gateway`/`VirtualService` resources |
| `istioNamespace` | string | `istio-system` | Namespace where Istio control plane is installed |
| `istioIngress` | string | `egressgateway` | Istio ingress gateway name |
| `istioEgress` | string | `ingressgateway` | Istio egress gateway name |
| `monitoring` | bool | `true` | Enable Prometheus `ServiceMonitor` resources |
| `healthCheck` | bool | `true` | Enable liveness and readiness probes |
| `jsonLogging` | bool | `false` | Output logs in JSON format |
| `disableLogFiles` | bool | `false` | Disable writing logs to disk |
| `traceSpec` | string | `*=info` | Log level specification (Liberty trace format) |
| `environment` | string | `production` | Deployment environment label (`production`, `staging`, etc.) |
| `cqrs` | bool | `false` | Enable CQRS pattern (requires trade-history service) |
| `pullSecret` | bool | `false` | Use an image pull secret |
| `pullSecretName` | string | — | Name of the image pull secret (required if `pullSecret: true`) |
| `specifyCerts` | bool | `false` | Mount custom TLS certificates |
| `certs` | string | — | PEM-encoded certificate(s) to trust (required if `specifyCerts: true`) |
| `proxyServer` | bool | `false` | Route egress through an HTTP proxy |
| `proxyServerAddress` | string | — | HTTP proxy URL (required if `proxyServer: true`) |

### `spec.global.opentelemetry`

Controls the OpenTelemetry Collector sidecar and instrumentation.

| Field | Type | Default | Description |
|---|---|---|---|
| `disable` | bool | `false` | Disable all OpenTelemetry instrumentation |
| `serviceName` | string | `trader` | Service name reported to the collector |
| `logExporter` | string | `otlp` | Log export protocol (`otlp`, `none`) |
| `metricExporter` | string | `otlp` | Metric export protocol |
| `traceExporter` | string | `otlp` | Trace export protocol |
| `agent.enabled` | bool | `false` | Deploy the OpenTelemetry Java agent |
| `collector.replicas` | int | `1` | Number of collector replicas |
| `collector.endpoint` | string | — | OTLP gRPC endpoint for the collector |
| `collector.backends` | list | — | Backends to export telemetry to (see below) |
| `autoscaling.enabled` | bool | `true` | Enable HPA for the collector |

Collector backend kinds: `azuremonitor`, `googlecloud`. Each requires a `secretName` containing provider credentials.

---

## `spec.broker`

The Broker service aggregates portfolios and coordinates trade operations.

| Field | Type | Default | Description |
|---|---|---|---|
| `image.repository` | string | `ghcr.io/ibmstocktrader/broker` | Container image repository |
| `image.tag` | string | `1.0.0` | Image tag |
| `replicas` | int | `1` | Number of pod replicas |
| `autoscale` | bool | `false` | Enable HPA |
| `cpuThreshold` | int | `75` | CPU % target for HPA scale-out |
| `maxReplicas` | int | `10` | Maximum HPA replica count |
| `url` | string | _(internal)_ | Internal service URL (leave as templated default) |

The same `image`, `replicas`, `autoscale`, `cpuThreshold`, `maxReplicas`, and `url` fields apply to all microservices below.

---

## Microservices

Each service shares the common fields described in `spec.broker` above. Services marked **optional** are disabled by default (`enabled: false`).

| Service | Field key | Optional | Notes |
|---|---|---|---|
| Broker | `broker` | No | Core service — always deployed |
| Portfolio | `portfolio` | No | Core service — always deployed |
| Stock Quote | `stockQuote` | No | Requires an IEX Cloud API key |
| Trader (JSP UI) | `trader` | No | Classic web UI |
| Account | `account` | Yes | Account management service |
| Cash Account | `cashAccount` | Yes | Requires `exchangeRateUrl` |
| Looper | `looper` | Yes | Load-testing harness |
| Messaging | `messaging` | Yes | Publishes loyalty events to Kafka/MQ |
| Notification (Slack) | `notificationSlack` | Yes | Slack webhook notifications |
| Notification (Twitter) | `notificationTwitter` | Yes | Twitter/X notifications |
| Tradr (React UI) | `tradr` | Yes | React-based alternative UI |
| Trade History | `tradeHistory` | Yes | Requires MongoDB |

### `spec.stockQuote` extra fields

| Field | Description |
|---|---|
| `iexApiKey` | IEX Cloud API key for live stock quotes |
| `iexTrading` | IEX Cloud API endpoint (default: `https://cloud.iexapis.com/stable/stock`) |
| `apiConnect` | IBM API Connect endpoint (alternative to IEX Trading) |
| `encryption.class` | Encryption class for stored quotes (`noneEncryptor`, `aesEncryptor`) |

### `spec.trader` extra fields

| Field | Description |
|---|---|
| `whiteLabelHeaderImage` | Custom header image filename (served from static assets) |
| `whiteLabelFooterImage` | Custom footer image filename |
| `whiteLabelLoginMessage` | Login page message text |

---

## `spec.database`

PostgreSQL connection settings. These values are overridden by the externally managed secret when `global.externalSecret: true`.

| Field | Default | Description |
|---|---|---|
| `kind` | `db2` | Database type. Use `postgres` for Azure Database for PostgreSQL |
| `host` | — | Database server hostname |
| `port` | `50000` | Port (`5432` for PostgreSQL) |
| `db` | `trader` | Database name |
| `id` | — | Username |
| `password` | — | Password |
| `ssl` | `false` | Enable TLS for database connections |

---

## `spec.redis`

| Field | Description |
|---|---|
| `urlWithCredentials` | Full Redis URL including credentials: `redis://:<password>@<host>:<port>` |
| `cacheInterval` | Stock quote cache TTL in seconds (default: `60`) |

---

## `spec.kafka`

Controls event streaming for the messaging and trade-history services.

| Field | Description |
|---|---|
| `kind` | Kafka flavour: `ibm-event-streams`, `apache-kafka` |
| `address` | Bootstrap broker address |
| `apiKey` | API key (SASL password) |
| `user` | SASL username (default: `token` for Event Streams) |
| `saslMechanism` | SASL mechanism (`PLAIN`) |
| `brokerTopic` | Topic for broker events |
| `portfolioTopic` | Topic for portfolio events |
| `accountTopic` | Topic for account events |
| `historyTopic` | Topic for trade history events |
| `cashAccountTopic` | Topic for cash account events |

---

## `spec.oidc`

Required when `global.auth: oidc`.

| Field | Description |
|---|---|
| `discoveryUrl` | OIDC discovery endpoint URL |
| `clientId` | OIDC application client ID |
| `clientSecret` | OIDC application client secret |
| `jwksUrl` | JSON Web Key Set URL |

### Azure AD / Entra ID example

```yaml
spec:
  global:
    auth: oidc
  oidc:
    discoveryUrl: https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration
    clientId: <app-registration-client-id>
    clientSecret: <app-registration-client-secret>
    jwksUrl: https://login.microsoftonline.com/<tenant-id>/discovery/v2.0/keys
```

---

## `spec.jwt`

JWT validation settings used by the Liberty runtime.

| Field | Default | Description |
|---|---|---|
| `audience` | `stock-trader` | Expected JWT audience claim |
| `issuer` | `http://stock-trader.ibm.com` | Expected JWT issuer claim |

---

## `spec.mq`

IBM MQ connection settings. Used by the messaging service.

| Field | Default | Description |
|---|---|---|
| `host` | — | MQ server hostname |
| `port` | `1414` | MQ listener port |
| `channel` | `DEV.APP.SVRCONN` | MQ channel name |
| `queueManager` | `stocktrader` | Queue manager name |
| `queue` | `NotificationQ` | Notification queue name |
| `id` | `app` | MQ username |
| `password` | — | MQ password |
| `kind` | `ibm-mq` | MQ flavour |

---

## `spec.vault`

HashiCorp Vault integration (alternative to ESO).

| Field | Default | Description |
|---|---|---|
| `enabled` | `false` | Enable Vault secret injection |
| `path` | — | Vault secret path |
| `role` | — | Vault Kubernetes auth role |
| `jwtPath` | `/var/run/secrets/kubernetes.io/serviceaccount` | Service account JWT path |

---

## `spec.ldap`

Required when `global.auth: ldap`.

| Field | Default | Description |
|---|---|---|
| `host` | `bluepages.ibm.com` | LDAP server hostname |
| `port` | `389` | LDAP port |
| `realm` | `BluePages` | Authentication realm |
| `baseDN` | `o=ibm.com` | Search base DN |
| `bindDN` | — | Bind DN for search |
| `bindPassword` | — | Bind password |
| `bindAuthMechanism` | `simple` | Bind authentication mechanism |
| `ssl` | `false` | Enable LDAPS |

---

## Minimal production example

The smallest viable CR for an Azure deployment using OIDC authentication and ESO-managed secrets:

```yaml
apiVersion: operators.ibm.com/v1
kind: StockTrader
metadata:
  name: stocktrader
  namespace: stock-trader
spec:
  global:
    auth: oidc
    externalSecret: true
    secretName: stock-trader-credentials
    ingress: true
    monitoring: true
  oidc:
    discoveryUrl: https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration
    clientId: <client-id>
    clientSecret: <client-secret>
    jwksUrl: https://login.microsoftonline.com/<tenant-id>/discovery/v2.0/keys
  stockQuote:
    iexApiKey: <your-iex-api-key>
  database:
    kind: postgres
    host: <postgres-host>
    port: 5432
    db: trader
    id: <user>
    password: <password>
    ssl: true
  redis:
    urlWithCredentials: redis://:<password>@<host>:6380
    cacheInterval: 60
```
