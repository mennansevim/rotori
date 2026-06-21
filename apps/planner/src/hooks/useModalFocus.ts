import { useEffect, useRef } from 'react';

const FOCUSABLE_SELECTOR =
  'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Modal için focus trap + Escape + auto-focus.
 * - Açıldığında en üst container'daki ilk focusable elemana odaklan
 * - Tab/Shift+Tab içeride wrap eder
 * - Escape onClose'u çağırır
 * - Kapanışta önceki aktif elemana focus döner
 *
 * Kullanım:
 *   const ref = useModalFocus<HTMLDivElement>(open, onClose);
 *   return <div ref={ref} ...>...</div>
 */
export function useModalFocus<T extends HTMLElement = HTMLDivElement>(
  open: boolean,
  onClose: () => void,
) {
  const containerRef = useRef<T | null>(null);

  useEffect(() => {
    if (!open) return;
    const container = containerRef.current;
    if (!container) return;
    const previouslyFocused = document.activeElement as HTMLElement | null;

    // İlk focusable elemana odaklan (ilk butona değil; container'a fallback)
    const first = container.querySelector<HTMLElement>(FOCUSABLE_SELECTOR);
    first?.focus();

    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onClose();
        return;
      }
      if (e.key !== 'Tab') return;
      const focusables = Array.from(
        container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR),
      ).filter((el) => !el.hasAttribute('disabled'));
      if (focusables.length === 0) {
        e.preventDefault();
        return;
      }
      const firstEl = focusables[0];
      const lastEl = focusables[focusables.length - 1];
      const active = document.activeElement as HTMLElement | null;
      if (e.shiftKey) {
        if (active === firstEl || !container.contains(active)) {
          e.preventDefault();
          lastEl.focus();
        }
      } else if (active === lastEl) {
        e.preventDefault();
        firstEl.focus();
      }
    };

    document.addEventListener('keydown', handleKey);
    return () => {
      document.removeEventListener('keydown', handleKey);
      previouslyFocused?.focus?.();
    };
  }, [open, onClose]);

  return containerRef;
}
