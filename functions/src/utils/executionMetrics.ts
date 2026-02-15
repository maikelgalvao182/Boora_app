/**
 * 📊 Execution Metrics — observabilidade leve para Cloud Functions
 *
 * Rastreia reads, writes, deletes e tempo de execução.
 * Emite um único structured log ao final (done/fail).
 */

export interface ExecutionMetricsOptions {
  executionId: string;
}

export interface ExecutionMetrics {
  addReads(n: number): void;
  addWrites(n: number): void;
  addDeletes(n: number): void;
  done(meta?: Record<string, unknown>): void;
  fail(error: unknown, meta?: Record<string, unknown>): void;
}

export function createExecutionMetrics(
  opts: ExecutionMetricsOptions
): ExecutionMetrics {
  const startMs = Date.now();
  let reads = 0;
  let writes = 0;
  let deletes = 0;

  return {
    addReads(n: number) {
      reads += n;
    },
    addWrites(n: number) {
      writes += n;
    },
    addDeletes(n: number) {
      deletes += n;
    },
    done(meta?: Record<string, unknown>) {
      const durationMs = Date.now() - startMs;
      console.log(
        JSON.stringify({
          severity: "INFO",
          message: "cf_execution_done",
          executionId: opts.executionId,
          durationMs,
          reads,
          writes,
          deletes,
          ...meta,
        })
      );
    },
    fail(error: unknown, meta?: Record<string, unknown>) {
      const durationMs = Date.now() - startMs;
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      console.error(
        JSON.stringify({
          severity: "ERROR",
          message: "cf_execution_fail",
          executionId: opts.executionId,
          durationMs,
          reads,
          writes,
          deletes,
          error: errorMessage,
          ...meta,
        })
      );
    },
  };
}
