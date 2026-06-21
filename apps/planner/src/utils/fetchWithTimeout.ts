/** AbortController + timeout wrapper around fetch.
 *  Caller's own AbortSignal (if provided) is composed with timeout. */
export async function fetchWithTimeout(
  input: RequestInfo | URL,
  init?: RequestInit & { timeoutMs?: number },
): Promise<Response> {
  const timeoutMs = init?.timeoutMs ?? 20_000;
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeoutMs);

  // Outer signal varsa onun abort'unu da bağla
  const outer = init?.signal;
  let outerCleanup: (() => void) | undefined;
  if (outer) {
    if (outer.aborted) {
      controller.abort();
    } else {
      const onAbort = () => controller.abort();
      outer.addEventListener('abort', onAbort);
      outerCleanup = () => outer.removeEventListener('abort', onAbort);
    }
  }

  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    window.clearTimeout(timer);
    outerCleanup?.();
  }
}
