import { useEffect, useRef, useState } from 'react';
import { searchAirports, type Airport } from '@japan-trip/shared';

interface Props {
  value?: string;
  valueLabel?: string;
  placeholder?: string;
  /** Yalnızca bu ülke kodlarındaki havaalanlarını listele (örn. ['TR'] veya ['JP']). */
  countryCodes?: string[];
  onSelect: (airport: Airport) => void;
}

export function AirportPicker({
  value,
  valueLabel,
  placeholder,
  countryCodes,
  onSelect,
}: Props) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const [highlight, setHighlight] = useState(0);
  const wrapRef = useRef<HTMLDivElement>(null);

  const results = open ? searchAirports(query, 8, countryCodes) : [];

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, []);

  const display = open ? query : valueLabel ?? '';

  const choose = (a: Airport) => {
    onSelect(a);
    setQuery('');
    setOpen(false);
  };

  return (
    <div className="airport-picker" ref={wrapRef}>
      <div className="airport-input-wrap">
        <span className="airport-input-icon">✈️</span>
        <input
          type="text"
          className="airport-input"
          placeholder={placeholder ?? 'Havaalanı, şehir veya ülke'}
          value={display}
          onFocus={() => {
            setOpen(true);
            setQuery('');
            setHighlight(0);
          }}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
            setHighlight(0);
          }}
          onKeyDown={(e) => {
            if (!open) return;
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              setHighlight((h) => Math.min(h + 1, results.length - 1));
            } else if (e.key === 'ArrowUp') {
              e.preventDefault();
              setHighlight((h) => Math.max(h - 1, 0));
            } else if (e.key === 'Enter' && results[highlight]) {
              e.preventDefault();
              choose(results[highlight]);
            } else if (e.key === 'Escape') {
              setOpen(false);
            }
          }}
        />
        {value && !open && <span className="airport-code-badge">{value}</span>}
      </div>
      {open && results.length > 0 && (
        <ul className="airport-dropdown" role="listbox">
          {results.map((a, i) => (
            <li
              key={a.iata}
              role="option"
              aria-selected={i === highlight}
              className={`airport-option${i === highlight ? ' active' : ''}`}
              onMouseEnter={() => setHighlight(i)}
              onMouseDown={(e) => {
                e.preventDefault();
                choose(a);
              }}
            >
              <span className="airport-option-code">{a.iata}</span>
              <span className="airport-option-city">{a.city}</span>
              <span className="airport-option-country">{a.countryName}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
