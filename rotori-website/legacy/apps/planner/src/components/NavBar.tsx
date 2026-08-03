import { useTranslation } from 'react-i18next';
import { STEPS, type StepId } from '../steps';
import { setLang } from '../i18n';

interface Props {
  step: StepId;
  onStep: (id: StepId) => void;
  completedSteps: Set<StepId>;
  onNewPlan: () => void;
  /** Rota tamamlanmadan sonraki adımları kilitle. */
  lockedSteps?: Set<StepId>;
}

export function NavBar({
  step,
  onStep,
  completedSteps,
  onNewPlan,
  lockedSteps,
}: Props) {
  const { t, i18n } = useTranslation();
  const otherLang = i18n.language?.startsWith('en') ? 'tr' : 'en';
  return (
    <header className="top-nav">
      <div className="top-nav-inner">
        <a href="/planner/" className="brand">
          <span className="brand-icon">✈️</span>
          <span>{t('nav.brand')}</span>
        </a>
        <div className="top-nav-actions">
          <button
            type="button"
            className="btn-ghost"
            onClick={() => setLang(otherLang as 'tr' | 'en')}
            title={otherLang.toUpperCase()}
            aria-label={`Language: ${otherLang.toUpperCase()}`}
          >
            🌐 {otherLang.toUpperCase()}
          </button>
          <button type="button" className="btn-ghost" onClick={onNewPlan}>
            {t('nav.newPlan')}
          </button>
          <a href="/viewer/" className="btn-ghost">
            {t('nav.guide')}
          </a>
        </div>
      </div>
      <div className="step-nav-wrap">
        <nav className="step-nav" aria-label="Plan steps">
          {STEPS.map((s) => {
            const locked = lockedSteps?.has(s.id) ?? false;
            return (
              <button
                key={s.id}
                type="button"
                className={`step-pill${step === s.id ? ' active' : ''}${completedSteps.has(s.id) ? ' done' : ''}${locked ? ' locked' : ''}`}
                onClick={() => !locked && onStep(s.id)}
                disabled={locked}
                aria-disabled={locked}
                title={locked ? t('errors.boundaryBody') : undefined}
              >
                <span className="step-num">
                  {locked
                    ? '🔒'
                    : completedSteps.has(s.id) && step !== s.id
                      ? '✓'
                      : s.num}
                </span>
                {t(`nav.${s.id}`, s.label)}
              </button>
            );
          })}
        </nav>
      </div>
    </header>
  );
}
