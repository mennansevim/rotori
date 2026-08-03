import { useMemo } from 'react';
import { JAPAN_TIPS } from '@japan-trip/shared';

/**
 * Küçük "hap bilgi" balonu. seed (gün numarası vb.) ile aynı bilgi
 * rerender'larda değişmez.
 */
export function TipBubble({ seed }: { seed: number }) {
  const tip = useMemo(() => {
    if (JAPAN_TIPS.length === 0) return null;
    const idx = Math.abs(seed) % JAPAN_TIPS.length;
    return JAPAN_TIPS[idx];
  }, [seed]);

  if (!tip) return null;

  return (
    <div className="tip-bubble" role="note">
      <span className="tip-bubble-emoji">💡</span>
      <span>{tip}</span>
    </div>
  );
}
