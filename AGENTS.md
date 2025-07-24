## commoncrawl-chunks-export-worker

A scalable EC2‐based Go worker that reads WARC chunks from CommonCrawl, processes them through a single weighted scheduler, and exports Parquet files to S3.

### Repository Layout

```
commoncrawl-chunks-export-worker/
├── AGENTS.md                 # Architecture notes & contributor guidelines
├── Dockerfile                # Containerize the worker
├── Makefile                  # Targets: `make build`, `make test`, `make docker`
├── README.md                 # (you are here) project overview & structure
├── build/ci.yml              # CI configuration (GitHub Actions)
├── cmd/
│   └── worker/
│       └── main.go           # Entrypoint: config, AWS SDK init, start scheduler & metrics loop
├── go.mod
├── go.sum.go                 # (should be renamed to `go.sum`)
└── internal/
    ├── client/               # Low‐level clients exposed to stages
    │   ├── s3/s3.go          # S3 upload helpers (AWS SDK v2)
    │   └── warc/warc.go      # CommonCrawl WARC download & decode
    │
    ├── config/config.go      # Environment & YAML config loader & validator
    │
    ├── scheduler/            # Combined queue & weighted scheduler logic
    │   ├── scheduler.go       # Core loop: snapshot, weight, pick, dispatch
    │   └── types.go           # TaskType enum, Snapshot struct, weight functions
    │
    └── worker/               # Task execution & stage dispatch
        └── worker.go         # Maps TaskTypes to client calls, manages Active counters
```

> **Note**: We intentionally merge the queue and scheduler into one package to keep the dispatch logic concise. Stage definitions live directly in `worker/`, calling into `client/` methods for implementation. If the package grows too large, we can split out `stages/` later.

---

### Metrics & Logging

* **Minimal stdout logs**: only fatal errors and panics are printed to stdout.
* **Operational metrics**: emitted via AWS CloudWatch `PutMetricData` (no extra HTTP server).

    * Every 15s the worker sends `QueueDepth` and `ActiveWorkers` per stage to CloudWatch under the `CommonCrawlWorker` namespace.
    * Configure AWS IAM role and region in your instance profile or env vars.
    * Use Grafana (with the CloudWatch datasource) or the CloudWatch Console to visualize metrics:

        * `QueueDepth{Stage="prep"}`
        * `ActiveWorkers{Stage="exportio"}`

### General Design

The worker is organized into the following key components to balance throughput, resource utilization, and simplicity:

1. **Scheduler**

    * Implements a single weighted scheduler that dynamically balances work across stages based on queue backlog and per-stage concurrency limits.
    * Periodically (e.g. every 10ms) snapshots queue lengths and active worker counts, computes weights, and selects the next task to dispatch.

2. **Worker/Executor**

    * Receives dispatched tasks from the scheduler and invokes the corresponding stage implementation in `internal/client`.
    * Tracks active task counts atomically to enforce each stage’s `MaxWorkers` cap.

3. **Clients/Stages**

    * **`client/warc`**: Downloads and decodes WARC chunks from CommonCrawl.
    * **`client/s3`**: Uploads processed Parquet files to S3 using the AWS SDK v2’s `PutObject` and multipart APIs.
    * Additional stage logic (e.g. Parquet aggregation) lives in the worker, calling into these low‐level clients.

4. **Metrics Loop**

    * Every 15s, snapshots and emits `QueueDepth` and `ActiveWorkers` metrics for each stage.
    * Sends metrics via CloudWatch `PutMetricData` to the `CommonCrawlWorker` namespace.

5. **Configuration & Initialization**

    * Loads environment variables and (optionally) YAML config via `internal/config`.
    * Initializes AWS SDK clients for S3 and CloudWatch.
    * Starts the scheduler and metrics loop concurrently.


### Data pipeline

Here’s are step-by-step transformation flow that covers the end-to-end pipeline:

1. **Read & Decode Parquet → `[]InputRecord`**

    * Simple row-by-row scan of the S3-backed Parquet files.

2. **Group by `GroupID` → `[]RequestJob`**

```go
// For each run of records with the same non-nil GroupID:
//    sort by Offset (already guaranteed)
//    StartOffset = first.Offset
//    EndOffset   = last.Offset + last.Length
//    Members     = list of each {Offset,Length}
// Solo records (GroupID==nil) become Jobs with one Member.
```

3. **Fetch from S3 → `FetchedJob`**

```go
// Use GetObject with Range: "bytes={StartOffset}-{EndOffset-1}"
// Read body entirely into Data []byte.
```

4. **Slice out each Member → `[]SliceResult`**

```go
for _, m := range job.Members {
 start := m.Offset - job.StartOffset
 end   := start + m.Length
 payload := fetched.Data[start:end]
 append(SliceResult{job.GroupID, job.WARCFilename, m.Offset, payload})
}
```

5. **Parse WARC payload → HTML → plaintext → `PlainTextRecord`**

```go
// wrap payload via gzip.NewReader + warcio.ArchiveIterator
// locate .ContentStream() for `response` record
// run HTMLToText(...) → text
// emit PlainTextRecord{GroupID, Filename, Offset, text}
```

6. **Write out as Parquet**

* Collect batches of `PlainTextRecord` (order doesn’t matter).
* Flush to S3 as new Parquet files.

---

### Why this is simple and extensible

* **Separation of concerns**: each type encapsulates exactly one stage’s contract.
* **Grouped fetches** avoid redundant S3 calls.
* **Slicing in memory** is just index math—no streaming complexity.
* **Decoding & HTML-to-text** live in the final map–transform.
* **Output model** is flat and self-contained (ready for downstream ML or analysis).

You can now unit-test each transformation in isolation, and if you later need richer metadata (timestamps, HTTP headers, full WARC headers) you can add fields to these structs without touching the flow.



