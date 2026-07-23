# Valkey Best Practices

Best practices for using Valkey (Redis-compatible open-source fork) as a pub/sub service, message queue, and cache in Rust applications.

## Overview

Valkey is the open-source replacement for Redis, maintained by the Linux Foundation under the BSD-3-Clause license. It is a drop-in replacement for Redis, compatible with all Redis protocols and clients.

> **Key Rule:** Valkey should **NOT** be used as a persistent store. Use it only for pub/sub, message queues (Streams), and caching. Split caching into a separate Valkey instance if queue performance is critical.

---

## Architecture Overview

The Valkey cluster serves three distinct purposes, each mapped to a different usage pattern:

- **Pub/Sub** — Real-time, fire-and-forget notifications (e.g., Server-Sent Events).
- **Streams** — Persistent job queues with exactly-once processing via consumer groups.
- **Cache** — TTL-based session and data caching.

If queue throughput is critical, run caching on a separate Valkey instance to avoid contention.

---

## Client Setup in Rust

### Valkey Client Wrapper

Create a thin wrapper around the `redis` crate (compatible with Valkey):

```rust
use crate::core_config;
use crate::event::Result;
use redis::aio::{MultiplexedConnection, PubSub};
use redis::Client;

#[derive(Debug, Clone)]
pub struct ValkeyClient {
    client: Client,
}

impl ValkeyClient {
    pub fn new() -> Result<Self> {
        let client = new_valkey_client()?;
        Ok(ValkeyClient { client })
    }

    pub async fn pub_sub(&self) -> Result<PubSub> {
        let pub_sub = self.client.get_async_pubsub().await?;
        Ok(pub_sub)
    }

    pub async fn conn(&self) -> Result<MultiplexedConnection> {
        let conn = self.client.get_multiplexed_tokio_connection().await?;
        Ok(conn)
    }

    pub fn client(&self) -> &Client {
        &self.client
    }
}

impl From<Client> for ValkeyClient {
    fn from(client: Client) -> Self {
        ValkeyClient { client }
    }
}

pub(in crate::event) fn new_valkey_client() -> Result<Client> {
    let conn_url = &core_config().VALKEY_URL;
    let client = Client::open(conn_url.as_str())?;
    Ok(client)
}
```

### Configuration

```rust
// In your core_config or similar
pub struct CoreConfig {
    pub VALKEY_URL: String,
}

// Example .env or config
// VALKEY_URL=redis://rust10x-valkey:6379
```

---

## Pub/Sub Pattern (VkHub)

Use pub/sub for **real-time, fire-and-forget notifications** such as Server-Sent Events (SSE).

### VkHub Implementation

```rust
use std::marker::PhantomData;
use crate::event::{Result, valkey::client::ValkeyClient};
use redis::{aio::PubSub, AsyncCommands};
use serde::{de::DeserializeOwned, Serialize};

#[derive(Clone, Debug)]
pub struct VkHub<T> {
    pub vkclient: ValkeyClient,
    _marker: PhantomData<T>,
}

impl<T> VkHub<T>
where
    T: Serialize + DeserializeOwned,
{
    pub fn new(vkclient: &ValkeyClient) -> Self {
        Self {
            vkclient: vkclient.clone(),
            _marker: PhantomData,
        }
    }

    pub async fn subscribe(&self, channel: &str) -> Result<PubSub> {
        let mut pubsub = self.vkclient.pub_sub().await?;
        pubsub.subscribe(channel).await?;
        Ok(pubsub)
    }

    pub async fn unsubscribe(&self, channel: &str) -> Result<()> {
        let mut pubsub = self.vkclient.pub_sub().await?;
        pubsub.unsubscribe(channel).await?;
        Ok(())
    }

    pub async fn publish_evt(&self, channel: &str, evt: T) -> Result<()> {
        let mut conn = self.vkclient.conn().await?;
        let evt = serde_json::to_string(&evt)?;
        let _: () = conn.publish(channel, evt).await?;
        Ok(())
    }
}
```

### Usage Example: SSE Notifications

```rust
let vkhub = VkHub::<SseNotificationEvent>::new(&vkclient);
let user_id = 123;
let channel = format!("sse-{}", user_id);

let notif = SseNotificationEvent::OtpCodeSend {
    user_id,
    code: "123456".to_string(),
};

vkhub.publish_evt(&channel, notif).await?;
```

---

## Stream Pattern (VkStream)

Use Valkey Streams for **persistent, exactly-once job queues** with consumer groups.

### VkStream Implementation

```rust
use std::{collections::HashMap, marker::PhantomData};
use crate::event::{valkey::client::ValkeyClient, Error, Result};
use redis::{
    from_redis_value,
    streams::{StreamReadOptions, StreamReadReply},
    AsyncCommands,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{Map, Value};
use tracing::warn;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(test, derive(PartialEq))]
pub struct VkStreamEntry {
    pub entry_id: String,
    pub data: HashMap<String, String>,
}

#[derive(Debug, Clone)]
pub struct VkStream<T> {
    pub stream: String,
    pub group: Option<String>,
    pub consumer: Option<String>,
    pub vkclient: ValkeyClient,
    _marker: PhantomData<T>,
}

impl<T> VkStream<T>
where
    T: Serialize + DeserializeOwned,
{
    pub fn new(stream: impl Into<String>, vkclient: &ValkeyClient) -> Self {
        Self {
            stream: stream.into(),
            group: None,
            consumer: None,
            vkclient: vkclient.clone(),
            _marker: PhantomData,
        }
    }

    pub fn with_group(mut self, group: impl Into<String>, consumer: impl Into<String>) -> Self {
        self.group = Some(group.into());
        self.consumer = Some(consumer.into());
        self
    }

    pub async fn next(&self, timeout_ms: usize) -> Result<Option<VkStreamEntry>> {
        let mut conn = self.vkclient.conn().await?;

        let opts = match (&self.group, &self.consumer) {
            (Some(g), Some(c)) => {
                StreamReadOptions::default()
                    .group(g, c)
                    .count(1)
                    .block(timeout_ms)
            }
            _ => StreamReadOptions::default().block(timeout_ms),
        };

        let ids = if self.group.is_some() { &[">"][..] } else { &["$"][..] };

        let res: Option<StreamReadReply> = conn
            .xread_options(&[&self.stream], ids, &opts)
            .await?;

        let Some(streams) = res else { return Ok(None); };
        let Some(entry) = streams.keys.first().and_then(|k| k.ids.first()) else {
            return Ok(None);
        };

        let mut data = HashMap::with_capacity(entry.map.len());
        for (k, v) in &entry.map {
            if let Ok(s) = from_redis_value::<String>(v) {
                data.insert(k.clone(), s);
            }
        }

        Ok(Some(VkStreamEntry {
            entry_id: entry.id.clone(),
            data,
        }))
    }

    pub async fn init_group(&self) -> Result<()> {
        let mut conn = self.vkclient.conn().await?;
        let res: core::result::Result<(), _> = conn
            .xgroup_create_mkstream(&self.stream, &self.group, "0")
            .await;

        match res {
            Ok(_) => Ok(()),
            Err(e) => {
                if let Some(code) = e.code() {
                    if code == "BUSYGROUP" {
                        warn!("->> CONSUMER GROUP ALREADY EXISTS, SKIPPING");
                        return Ok(());
                    }
                }
                Err(Error::Redis(e))
            }
        }
    }

    pub async fn ack(&self, entry_id: &str) -> Result<()> {
        if let Some(group) = &self.group {
            let mut conn = self.vkclient.conn().await?;
            let _: () = conn.xack(&self.stream, group, &[entry_id]).await?;
        }
        Ok(())
    }

    pub async fn add(&self, data: &T) -> Result<()> {
        let mut conn = self.vkclient.conn().await?;
        let data = prepare_for_add(&data)?;
        let _: String = conn.xadd(&self.stream, "*", &data).await?;
        Ok(())
    }
}
```

### Stream Entry Deserialization

```rust
impl VkStreamEntry {
    pub fn deserialize_as<T>(&self) -> Result<T>
    where
        T: DeserializeOwned,
    {
        let mut map = Map::with_capacity(self.data.len());
        for (k, v) in &self.data {
            let val = serde_json::from_str(v).unwrap_or(Value::String(v.clone()));
            map.insert(k.clone(), val);
        }
        let value = Value::Object(map);
        serde_json::from_value(value).map_err(Into::into)
    }

    pub fn deserialize_as_new<T>(&self) -> Result<T>
    where
        T: DeserializeOwned,
    {
        lib_utils::serde::from_hashmap::<T>(self.data.clone()).map_err(Into::into)
    }
}

pub fn prepare_for_add<T: Serialize>(data: &T) -> Result<Vec<(String, String)>> {
    let value = serde_json::to_value(data)?;
    let object = match value {
        Value::Object(map) => map,
        _ => return Err(Error::ExpectedObjectLikeValue),
    };

    Ok(object
        .into_iter()
        .map(|(k, v)| {
            let str_val = match v {
                Value::String(s) => s,
                _ => v.to_string(),
            };
            (k, str_val)
        })
        .collect())
}
```

---

## Worker Pattern

Workers bridge application events to Valkey streams or process job queues.

### OrgWorker: Application Event Bridge

```rust
use crate::Result;
use lib_core::event::{
    types::app_event::{AppEvent, SseNotificationEvent},
    valkey::{hub::VkHub, stream::VkStream},
};
use lib_event::unbounded::Rx;
use tracing::{debug, info};

pub struct OrgWorker {
    stream: VkStream<AppEvent>,
    hub: VkHub<SseNotificationEvent>,
}

impl OrgWorker {
    pub fn start(
        stream: VkStream<AppEvent>,
        hub: VkHub<SseNotificationEvent>,
        rx: Rx<AppEvent>,
    ) -> Result<()> {
        let org_worker = OrgWorker { stream, hub };
        tokio::spawn(async move {
            org_worker.start_worker(rx).await
        });
        Ok(())
    }

    async fn start_worker(&self, mut rx: Rx<AppEvent>) -> Result<()> {
        debug!("->> STARTING WORKER");
        while let Ok(evt) = rx.recv().await {
            info!("OrgEvent RX ->> {evt:?}");
            match evt {
                AppEvent::SseNotif(notif) => {
                    let user_id = extract_user_id(&notif);
                    let channel = format!("sse-{}", user_id);
                    self.hub.publish_evt(&channel, notif).await?;
                }
                _ => self.send_to_redis(evt).await?,
            }
        }
        Ok(())
    }

    async fn send_to_redis(&self, evt: AppEvent) -> Result<()> {
        let _ = self.stream.add(&evt).await?;
        Ok(())
    }
}

fn extract_user_id(notif_event: &SseNotificationEvent) -> i64 {
    match notif_event {
        SseNotificationEvent::OrgUserKick { user_id, .. } => *user_id,
        SseNotificationEvent::CallStatusChange { user_id, .. } => *user_id,
        SseNotificationEvent::OtpCodeSend { user_id, .. } => *user_id,
    }
}
```

### JobWorker: Job Queue Processor

```rust
use crate::Result;
use lib_core::event::{
    types::app_event::JobEvent,
    valkey::stream::VkStream,
};
use lib_event::unbounded::Rx;
use tracing::{debug, info};

pub struct JobWorker {
    stream: VkStream<JobEvent>,
}

impl JobWorker {
    pub fn start(stream: VkStream<JobEvent>, rx: Rx<JobEvent>) -> Result<()> {
        let worker = JobWorker { stream };
        tokio::spawn(async move {
            worker.start_worker(rx).await
        });
        Ok(())
    }

    async fn start_worker(&self, mut rx: Rx<JobEvent>) -> Result<()> {
        debug!("->> STARTING JOB WORKER");
        while let Ok(evt) = rx.recv().await {
            info!("JobEvent RX ->> {evt:?}");
            self.send_to_redis(evt).await?;
        }
        Ok(())
    }

    async fn send_to_redis(&self, evt: JobEvent) -> Result<()> {
        let _ = self.stream.add(&evt).await?;
        Ok(())
    }
}
```

---

## Event Types

Define strongly-typed events for all queue communication:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AppEvent {
    #[serde(rename = "OrgDataNew")]
    OrgDataNew {
        ent_type: String,
        org_id: i64,
        doc_id: i64,
    },
    #[serde(rename = "SseNotif")]
    SseNotif(SseNotificationEvent),
    #[serde(rename = "MediaNew")]
    MediaNew {
        wks_id: i64,
        media_id: i64,
        media_mime_type: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum SseNotificationEvent {
    #[serde(rename = "OrgUserKick")]
    OrgUserKick { user_id: i64, org_id: i64 },
    #[serde(rename = "CallStatusChange")]
    CallStatusChange { user_id: i64, status: String },
    #[serde(rename = "OtpCodeSend")]
    OtpCodeSend { user_id: i64, code: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum JobEvent {
    #[serde(rename = "VidInit")]
    VidInit { media_id: i64 },
    #[serde(rename = "VidScaler")]
    VidScaler { media_id: i64, resolution: String },
}
```

---
## Kubernetes Deployment

### Valkey Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rust10x-valkey
  namespace: rust10x-web-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rust10x-valkey
  template:
    metadata:
      labels:
        app: rust10x-valkey
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: valkey
          image: valkey/valkey:8.1.3-bookworm
          ports:
            - containerPort: 6379
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

### Valkey Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rust10x-valkey
  namespace: rust10x-web-app
spec:
  ports:
    - port: 6379
  selector:
    app: rust10x-valkey
```

---

## Queue Architecture Patterns

### Application Queues vs. Job Queues

| Type | Purpose | Example |
|------|---------|---------|
| **Application Queues** | Data and notification events | `MediaNew`, `OrgDataNew` |
| **Job Queues** | Work to be done by a service | `VidInitJob`, `VidScalerJob` |

### Bridge Pattern

Bridges connect Application Queues to Job Queues. By best practice, bridges live within their corresponding Job Service container.

Flow: Application Queue event is received by a Bridge Worker, which transforms it and pushes it to a Job Queue. For example, a `MediaNew` event from the App Queue is bridged to a `VidInitJob` on the Job Queue.

### Consumer Groups for Exactly-Once Processing

```rust
// Initialize group once at startup
let stream = VkStream::<JobEvent>::new("VidScalerJob", &vkclient)
    .with_group("VidScalerJob", &hostname);
stream.init_group().await?;

// Multiple instances compete for messages
// Only one instance receives each message
loop {
    if let Some(entry) = stream.next(5000).await? {
        let job: VidScalerJob = entry.deserialize_as_new()?;
        process_job(job).await?;
        stream.ack(&entry.entry_id).await?;
    }
}
```

---

## Performance Considerations


### Memory Usage

| Pattern | Memory Impact | Recommendation |
|---------|--------------|----------------|
| Pub/Sub | Low (fire-and-forget) | Use for real-time notifications |
| Streams | Medium (persistent) | Set `MAXLEN` or use `XTRIM` |
| Cache | High (TTL-based) | Set explicit TTLs, monitor memory |

### Stream Trimming

```rust
// Trim stream to keep only last 1000 entries
let _: () = conn
    .xtrim(&stream_key, redis::streams::StreamMaxlen::Approx(1000))
    .await?;
```

---

## Tips

- **Use `PhantomData<T>`** in `VkHub` and `VkStream` for zero-cost type safety at compile time.
- **Always call `init_group()`** before consuming from a stream with a consumer group.
- **Acknowledge entries promptly** with `.ack()` to prevent pending list growth.
- **Use `timeout_ms = 0`** in `.next()` for indefinite blocking (worker pattern).
- **Separate pub/sub and stream connections** — pub/sub connections cannot issue regular commands.
- **Use `serde_json` for event serialization** — human-readable, language-agnostic, debuggable.
- **Tag events with `#[serde(tag = "type")]`** for discriminated union deserialization.
- **Run Valkey as non-root** in Kubernetes (`runAsUser: 1000`).
- **Drop all capabilities** in container security context for defense in depth.
- **Use `xgroup_create_mkstream`** to auto-create streams when creating consumer groups.
- **Handle `BUSYGROUP` errors** gracefully — idempotent initialization is key.
- **Test with real Valkey instance** in integration tests — use testcontainers or a shared test instance.
