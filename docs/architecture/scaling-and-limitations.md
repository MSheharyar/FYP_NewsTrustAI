# Scaling & Limitations of the NewsTrustAI News Database

## Why a flat-file JSON database was the right FYP choice

The news corpus (~36 k articles) is stored as a single JSON file loaded into RAM at startup. This was a deliberate, time-bounded engineering decision:

- **Zero infrastructure cost.** No database server to configure, no schema migrations, no connection pooling. The team could focus entirely on the NLP pipeline.
- **Fast iteration.** Adding new scraped articles is a file-append operation; the mtime-based cache invalidation in `db/reader.py` picks up changes automatically without a restart.
- **Corpus fits in RAM.** 36 k articles with title + summary + body average ~1 KB each ≈ 36 MB — negligible on any modern server.
- **BM25 indexing is trivially fast at this scale.** Rebuilding the `rank-bm25` index takes ~0.3 s at startup; there is no query overhead beyond RAM lookups.

## Current limits

| Constraint | Impact |
|-----------|--------|
| Single-process, in-memory BM25 index | Cannot scale horizontally; every new server instance rebuilds its own index |
| Full corpus loaded at startup | Memory grows linearly with corpus size; impractical beyond ~500 k articles |
| No concurrent write isolation | Appending to the file while a request reads it can cause a partial-read on Windows without the mtime guard |
| No full-text query planner | BM25 over a flat list is O(n); query latency grows linearly with corpus size |

## Immediate mitigation already in place

The **TTL + LRU result cache** (`services/result_cache.py`) absorbs repeat and viral-claim traffic. A claim checked once at 09:00 is served from cache for 6 hours without touching the BM25 index, GDELT, or the HuggingFace API. This is the most impactful single change for a Pakistan news context where the same claim circulates across millions of WhatsApp messages.

## Migration path — three stages

### Stage 1: SQLite + FTS5 (drop-in, ~1 day effort)

Replace the JSON file with an SQLite database (`news.db`). The built-in FTS5 extension provides keyword retrieval without loading the corpus into RAM. The BM25 scoring is handled inside SQLite; `db/reader.py` becomes a `sqlite3` cursor call. Horizontal scaling is still single-writer, but read replicas are trivial with SQLite in WAL mode.

**Unlocks:** Corpus scales to ~5 M articles; memory footprint drops to essentially zero; concurrent reads are safe.

### Stage 2: Vector store for semantic re-ranking (FAISS / pgvector)

The NLI re-ranking step (`text_verifier.py`) currently retrieves BM25 top-100 then scores with a cross-encoder. Replacing the initial retrieval with a dense vector index (FAISS `IndexFlatIP` on `sentence-transformers/all-MiniLM-L6-v2` embeddings, or pgvector inside PostgreSQL) gives semantic recall that BM25 misses for paraphrase-heavy Urdu-translated headlines.

**Unlocks:** Better recall for paraphrased claims; the index can be sharded across GPUs for sub-10 ms retrieval at 10 M article scale.

### Stage 3: Decouple inference from the API layer

Move BERT, the NLI cross-encoder, and the Urdu HuggingFace call behind a dedicated inference service (TorchServe, Triton, or a simple FastAPI microservice on a GPU node). The main API layer becomes stateless and can scale horizontally behind a load balancer; inference is the only bottleneck and scales independently.

**Unlocks:** True horizontal API scaling; model versioning without API downtime; cost isolation (GPU only runs during inference bursts).

## Summary

The flat-file approach was optimal for FYP scope. The staged migration above takes the system from a single-server prototype to a production-grade architecture without changing the core 7-stage verification logic. The result cache already addresses the most realistic scaling pressure (viral claims) within the current architecture.

See also: [FYP feature status](../FYP-feature-status.md)
