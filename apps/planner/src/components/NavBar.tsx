import { STEPS, type StepId } from '../steps';

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
  return (
    <header className="top-nav">
      <div className="top-nav-inner">
        <a href="/planner/" className="brand">
          <span className="brand-icon">✈️</span>
          <span>Seyahat</span>
        </a>
        <div className="top-nav-actions">
          <button type="button" className="btn-ghost" onClick={onNewPlan}>
            Yeni plan
          </button>
          <a href="/viewer/" className="btn-ghost">
            Rehber
          </a>
        </div>
      </div>
      <div className="step-nav-wrap">
        <nav className="step-nav" aria-label="Plan adımları">
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
                title={locked ? 'Önce Rota adımını tamamlayın' : undefined}
              >
                <span className="step-num">
                  {locked
                    ? '🔒'
                    : completedSteps.has(s.id) && step !== s.id
                      ? '✓'
                      : s.num}
                </span>
                {s.label}
              </button>
            );
          })}
        </nav>
      </div>
    </header>
  );
}
