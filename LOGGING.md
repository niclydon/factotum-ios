# Logging Standards

This document defines the tiered logging framework used across all projects. Every repo's CLAUDE.md references this file. Follow these rules when writing any code.

---

## Core Principle

**Every new feature, handler, background process, or non-trivial function MUST include logging at every significant step.** This is not optional. When something breaks, logs are the only way to understand what happened without blind debugging.

---

## Log Levels

All code MUST implement a tiered logging system with four levels. Each component supports a configurable log level (via environment variable, config, or constructor parameter) that controls verbosity:

| Level | When to use | What to log |
|-------|-------------|-------------|
| `minimal` | Production steady-state | Errors and warnings only. Things that need attention. |
| `normal` | Production default | Errors, warnings, and key lifecycle events (startup, shutdown, job completion, API responses). Enough to understand what happened at a high level. |
| `verbose` | Active monitoring / new deploys | Everything in `normal` plus: function entry/exit, conditional branch outcomes, input/output summaries (status codes, byte counts, row counts), timing for slow operations. |
| `debug` | Active troubleshooting | Everything in `verbose` plus: raw request/response bodies (truncated), intermediate state, poll cycle details (even when empty), full error stack traces, variable values at decision points. |

---

## Implementation by Language

### TypeScript / Node.js

Use a `LOG_LEVEL` environment variable (`minimal` | `normal` | `verbose` | `debug`), defaulting to `normal`.

**Logger factory pattern:**
```typescript
import { createLogger } from './lib/logger'; // or './lib/console-logger'

const logger = createLogger('component-name');

logger.logMinimal('Error:', error);           // Always prints (errors/warnings)
logger.log('Job completed:', result);          // Prints at normal+
logger.logVerbose('Entering function', args);  // Prints at verbose+
logger.logDebug('Raw response:', body);        // Prints at debug only

const stop = logger.time('operationName');     // Starts timer
// ... do work ...
stop();                                        // Logs elapsed ms at verbose+
```

### Swift (iOS / macOS)

Use a `logLevel` property on the main service/daemon class, configurable via `.env` file, UserDefaults, or launch argument. Default to `normal`.

**Logger singleton pattern:**
```swift
let logger = Logger.shared

logger.logMinimal("service", "Error:", error)   // Always prints
logger.log("service", "Sync complete")           // Prints at normal+
logger.logVerbose("service", "Processing", id)   // Prints at verbose+
logger.logDebug("service", "Raw response:", body) // Prints at debug only

let stop = logger.time("service", "operation")   // Starts timer
// ... do work ...
stop()                                            // Logs elapsed ms at verbose+
```

### Python

Use a `LOG_LEVEL` environment variable, defaulting to `normal`.

```python
import os

LOG_LEVEL = os.environ.get('LOG_LEVEL', 'normal')
_LEVELS = {'minimal': 0, 'normal': 1, 'verbose': 2, 'debug': 3}
_N = _LEVELS.get(LOG_LEVEL, 1)

def log_minimal(*args): print('[component]', *args)
def log(*args):
    if _N >= 1: print('[component]', *args)
def log_verbose(*args):
    if _N >= 2: print('[component]', *args)
def log_debug(*args):
    if _N >= 3: print('[component]', *args)
```

### Shell (Bash/Zsh)

```bash
case "${LOG_LEVEL:-normal}" in
  minimal) _LOG_LEVEL=0 ;;
  verbose) _LOG_LEVEL=2 ;;
  debug)   _LOG_LEVEL=3 ;;
  *)       _LOG_LEVEL=1 ;;  # normal
esac

log()         { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
log_verbose() { [[ $_LOG_LEVEL -ge 2 ]] && log "$*" || true; }
log_debug()   { [[ $_LOG_LEVEL -ge 3 ]] && log "DEBUG: $*" || true; }
```

---

## Rules (all levels, all languages)

1. **Log entry** into every function that does real work (API calls, DB queries, file I/O, process execution) — at `verbose` or above
2. **Log the outcome** of every conditional branch that matters (success, failure, skip, fallback) — at `verbose` or above
3. **Log input/output summaries** for external calls (API status codes, byte counts, row counts, process exit codes) — at `normal` or above
4. **Log timing** for operations that could be slow (network requests, process execution, LLM calls) — at `verbose` or above
5. **Use structured prefixes**: `[component-name]` for all log lines
6. **Include context** to reconstruct what happened: IDs, counts, truncated previews of data
7. **Never silently swallow errors** — at minimum log a warning before returning/continuing (all levels)
8. **Background workers and polling loops**: log each poll cycle and what was found (even if empty) — at `debug` level
9. **Log raw response bodies** from external APIs — at `debug` level, truncated to 500 chars
10. **Write logging code for ALL levels up front** — never plan to "add debug logging later"

---

## Troubleshooting Protocol

When diagnosing issues:

1. **First**, set the log level to `debug` and reproduce the issue
2. **Read the logs** — look for error messages, unexpected response bodies, status codes, and timing anomalies
3. **Never debug blind** — if logs don't explain what's happening, add more logging before making code changes
4. **Log raw responses** from external APIs and services at `debug` level — type mismatches, unexpected JSON shapes, and encoding issues are common root causes
