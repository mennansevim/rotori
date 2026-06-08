import { STEPS, type StepId } from '../steps';

interface Props {
  step: StepId;
  onStep: (id: StepId) => void;
  completedSteps: Set<StepId>;
  onNewPlan: () => void;
}

export function NavBar({ step, onStep, completedSteps, onNewPlan }: Props) {
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
          {STEPS.map((s) => (
            <button
              key={s.id}
              type="button"
              className={`step-pill${step === s.id ? ' active' : ''}${completedSteps.has(s.id) ? ' done' : ''}`}
              onClick={() => onStep(s.id)}
            >
              <span className="step-num">{completedSteps.has(s.id) && step !== s.id ? '✓' : s.num}</span>
              {s.label}
            </button>
          ))}
        </nav>
      </div>
    </header>
  );
}
