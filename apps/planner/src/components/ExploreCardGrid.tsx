export interface ExploreCardItem {
  id: string;
  name: string;
  emoji?: string;
  category?: string;
  meta?: string;
}

interface Props {
  items: ExploreCardItem[];
  isSelected: (item: ExploreCardItem) => boolean;
  onToggle: (item: ExploreCardItem) => void;
  feedback?: Record<string, string>;
}

export function ExploreCardGrid({ items, isSelected, onToggle, feedback }: Props) {
  return (
    <div className="explore-card-grid" role="list">
      {items.map((item) => {
        const selected = isSelected(item);
        const fb = feedback?.[item.id];
        return (
          <button
            key={item.id}
            type="button"
            role="listitem"
            className={`explore-card${selected ? ' selected' : ''}`}
            aria-pressed={selected}
            onClick={() => onToggle(item)}
          >
            {selected && (
              <span className="explore-card-check" aria-hidden>
                ✓
              </span>
            )}
            <span className="explore-card-emoji" aria-hidden>
              {item.emoji ?? '📍'}
            </span>
            <span className="explore-card-title">{item.name}</span>
            {item.meta && <span className="explore-card-meta">{item.meta}</span>}
            {fb && <span className="explore-card-feedback">{fb}</span>}
          </button>
        );
      })}
    </div>
  );
}
