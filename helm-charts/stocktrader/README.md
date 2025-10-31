# IBM Stock Trader Helm Chart

## Introduction

This helm chart installs and configures the IBM Stock Trader microservices.
Nowadays, generally the operator in the sibling `stocktrader-operator` repo
is used instead; that operator wraps this helm chart.

## Prerequisites

### Database Options

The Stock Trader application requires a relational (JDBC-compliant) database. You have two options:

#### Option 1: Internal PostgreSQL (Recommended for Development)
The chart includes PostgreSQL as a subchart dependency. Simply set `postgresql.enabled: true` in your values file.
The chart will automatically configure the connection parameters.

#### Option 2: External Database
You can use your own database instance (DB2, PostgreSQL, MySQL, etc.) by:
- Setting `database.type: external` 
- Configuring the `database.external.*` values with your connection details

### Optional Dependencies

The following dependencies are optional and can be enabled as either internal subcharts or external services:

* **Redis** - Enables stock quote caching for improved performance
  - Internal: Set `redis.enabled: true`
  - External: Configure `redis.urlWithCredentials`
  
* **MongoDB** - Enables Trade History and return-on-investment calculations
  - Internal: Set `mongodb.enabled: true`
  - External: Configure `mongo.connectionString`
  
* **Kafka** - Enables event streaming and CQRS patterns
  - Internal: Set `kafka.enabled: true`
  - External: Configure `kafka.address` (e.g., IBM Event Streams)
  
* **IBM MQ or ActiveMQ** - Enables notifications (external only)
  - Configure `mq.host`, `mq.port`, etc.
  
* **IBM Operational Decision Manager** - Enables loyalty level determination (external only)
  - Configure `odm.url`
  
* **IBM Cloudant** - Enables account metadata storage (external only)
  - Configure `cloudant.url`, `cloudant.host`, etc.

## Configuration

The following table lists the main configurable parameters of this chart:

### Database Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `database.type` | `internal` to use subchart, `external` for your own DB | `internal` |
| `database.kind` | Database type (PostgreSQL, DB2, MySQL, etc.) | `PostgreSQL` |
| `database.external.host` | External database hostname | `db2inst1` |
| `database.external.port` | External database port | `50000` |
| `database.external.id` | External database username | `db2inst1` |
| `database.external.password` | External database password | `db2inst1` |
| `database.external.db` | External database name | `trader` |
| `database.external.ssl` | Enable SSL for external database | `false` |

### PostgreSQL Subchart Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `postgresql.enabled` | Enable PostgreSQL subchart | `true` |
| `postgresql.auth.username` | PostgreSQL username | `stocktrader` |
| `postgresql.auth.password` | PostgreSQL password | `changeme` |
| `postgresql.auth.database` | PostgreSQL database name | `trader` |
| `postgresql.primary.persistence.enabled` | Enable persistent storage | `true` |
| `postgresql.primary.persistence.size` | Storage size | `2Gi` |

### Redis Subchart Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `redis.enabled` | Enable Redis subchart | `false` |
| `redis.cacheInterval` | Cache interval in seconds | `60` |
| `redis.architecture` | Redis architecture (standalone/replication) | `standalone` |
| `redis.auth.enabled` | Enable Redis authentication | `false` |
| `redis.master.persistence.enabled` | Enable persistent storage | `true` |
| `redis.master.persistence.size` | Storage size | `1Gi` |

### MongoDB Subchart Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `mongodb.enabled` | Enable MongoDB subchart | `false` |
| `mongodb.auth.username` | MongoDB username | `stocktrader` |
| `mongodb.auth.password` | MongoDB password | `changeme` |
| `mongodb.auth.database` | MongoDB database name | `tradehistory` |
| `mongodb.persistence.enabled` | Enable persistent storage | `true` |
| `mongodb.persistence.size` | Storage size | `2Gi` |

### Kafka Subchart Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `kafka.enabled` | Enable Kafka subchart | `false` |
| `kafka.brokerTopic` | Broker events topic | `broker` |
| `kafka.portfolioTopic` | Portfolio events topic | `portfolio` |
| `kafka.accountTopic` | Account events topic | `account` |
| `kafka.cashAccountTopic` | Cash account events topic | `cash-account` |
| `kafka.historyTopic` | Trade history topic | `history` |
| `kafka.controller.replicaCount` | Number of Kafka controllers | `1` |
| `kafka.persistence.enabled` | Enable persistent storage | `true` |
| `kafka.persistence.size` | Storage size | `2Gi` |

### Microservice Configuration

| Parameter                           | Description                                         | Default                                                                         |
| ----------------------------------- | ----------------------------------------------------| --------------------------------------------------------------------------------|
| | | |
| broker.image.repository | image repository |  ghcr.io/ibmstocktrader/broker
| broker.image.tag | image tag | latest
| | | |
| portfolio.image.repository | image repository |  ghcr.io/ibmstocktrader/portfolio
| portfolio.image.tag | image tag | latest
| | | |
| stockQuote.image.repository | image repository | ghcr.io/ibmstocktrader/stock-quote
| stockQuote.image.tag | image tag | latest
| | | |
| brokerCQRS.enabled | Deploy broker-CQRS microservice | false
| brokerCQRS.image.repository | image repository |  ghcr.io/ibmstocktrader/broker-cqrs
| brokerCQRS.image.tag | image tag | latest
| | | |
| account.enabled | Deploy account microservice | false
| account.image.repository | image repository | ghcr.io/ibmstocktrader/account
| account.image.tag | image tag | latest
| | | |
| trader.enabled | Deploy trader microservice | true
| trader.image.repository | image repository | ghcr.io/ibmstocktrader/trader
| trader.image.tag | image tag | basicregistry
| | | |
| tradr.enabled | Deploy tradr microservice | false
| tradr.image.repository | image repository | ghcr.io/ibmstocktrader/tradr
| tradr.image.tag | image tag | latest
| | | |
| messaging.enabled | Deploy messaging microservice | false
| messaging.image.repository | image repository | ghcr.io/ibmstocktrader/messaging
| messaging.image.tag | image tag | latest
| | | |
| notificationSlack.enabled | Deploy notification-slack microservice | false
| notificationSlack.image.repository | image repository | ghcr.io/ibmstocktrader/notification-slack
| notificationSlack.image.tag | image tag | latest
| | | |
| notificationTwitter.enabled | Deploy notification-twitter microservice | false
| notificationTwitter.image.repository | image repository | ghcr.io/ibmstocktrader/notification-twitter
| notificationTwitter.image.tag | image tag | latest
| | | |
| looper.enabled | Deploy looper microservice | false
| looper.image.repository | image repository | ghcr.io/ibmstocktrader/looper
| looper.image.tag | image tag | latest
| | | |
| cashAccount.enabled | Deploy cash account microservice | false
| cashAccount.image.repository | image repository | ghcr.io/ibmstocktrader/collector
| cashAccount.image.tag | image tag | latest

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`.

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart.

## Building and Deploying the Chart

After cloning this repository and changing directory into it, just run `helm package stocktrader` to produce the stocktrader-2.0.0.tgz file.

It is also handy to change directory into the `stocktrader` directory (where the Chart.yaml is) and run `helm lint` to validate the helm chart.

## Installing the Chart

You can install the chart by setting the current directory to the folder where this chart is located and running the following command:

```console
helm install cjot stocktrader-2.0.0.tgz -n stocktrader . 
```

This sets the Helm release name to `cjot` and creates all Kubernetes resources in a namespace called `stocktrader`.

Note you need to make sure that the namespace to which you install it has an image policy allowing it to pull images from
the GitHub Container Registry (unless you have built the sample yourself and are pulling it from your local Docker image registry).


## Uninstalling the Chart

```console
$ helm delete --purge stocktrader --tls
```
