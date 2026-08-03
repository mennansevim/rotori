import { useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { NavBar } from './components/NavBar';
import { OfflineIndicator } from './components/OfflineIndicator';
import { useModalFocus } from './hooks/useModalFocus';
import { WelcomeStep } from './components/steps/WelcomeStep';
import { JourneyStep } from './components/steps/JourneyStep';
import { TitleStep } from './components/steps/TitleStep';
import { FoodStep } from './components/steps/FoodStep';
import { PlanStep } from './components/steps/PlanStep';
import { ExploreStep } from './components/steps/ExploreStep';
import { PublishStep } from './components/steps/PublishStep';
import { HotelsStep, hotelsComplete } from './components/steps/HotelsStep';
import { useTripDraft } from './hooks/useTripDraft';
import { STEPS, type StepId } from './steps';

function stepIndex(id: StepId) {
  return STEPS.findIndex((s) => s.id === id);
}

export default function App() {
  const { t } = useTranslation();
  const {
    trip,
    updateTrip,
    undo,
    exportJson,
    importJson,
    startFresh,
    loadJapanTemplate,
    username,
  } = useTripDraft();
  const [step, setStep] = useState<StepId>('welcome');
  const [showNewModal, setShowNewModal] = useState(false);
  const newModalRef = useModalFocus<HTMLDivElement>(showNewModal, () =>
    setShowNewModal(false),
  );

  const completedSteps = useMemo(() => {
    const done = new Set<StepId>();
    const dests = trip.preferences.destinations ?? [];
    const hasRoute =
      (trip.preferences.originCity?.trim() || trip.flights.outbound[0]?.city?.trim()) &&
      dests.length > 0 &&
      dests.every((d) => d.city.trim());
    if (hasRoute && trip.preferences.travelDates.start) done.add('journey');
    if (
      trip.title.trim() &&
      trip.title !== 'Yeni seyahat' &&
      trip.title !== 'Japonya Turu'
    )
      done.add('title');
    if (hotelsComplete(trip)) done.add('hotels');
    if ((trip.preferences.destinationFood ?? []).some((f) => f.dietaryTags.length > 0 || f.foodLikes.length > 0))
      done.add('food');
    if (trip.days.some((d) => d.items.length > 0)) done.add('plan');
    done.add('publish');
    return done;
  }, [trip]);

  const i = stepIndex(step);
  const goNext = () => {
    if (i < STEPS.length - 1) setStep(STEPS[i + 1].id);
  };
  const goPrev = () => {
    if (i > 0) setStep(STEPS[i - 1].id);
  };

  const confirmNewPlan = () => {
    startFresh();
    setStep('welcome');
    setShowNewModal(false);
  };

  const startWithJapanPlan = () => {
    loadJapanTemplate();
    setStep('journey');
    setShowNewModal(false);
  };

  const canContinueJourney =
    (trip.preferences.originCity?.trim() || trip.flights.outbound[0]?.city?.trim()) &&
    (trip.preferences.destinations ?? []).length > 0 &&
    (trip.preferences.destinations ?? []).every((d) => d.city.trim());

  // Plan adımı çalıştırılıp en az bir aktivite üretilmeden yayın yapılamaz —
  // aksi halde viewer boş ekran açar.
  const planReady = useMemo(
    () => trip.days.some((d) => d.items.length > 0),
    [trip.days],
  );

  // Rota tamamlanmadıysa sonraki adımları, plan boşsa yayın adımını kilitle
  // (welcome ve journey her zaman serbest).
  const lockedSteps = useMemo<Set<StepId>>(() => {
    const locked = new Set<StepId>();
    if (!canContinueJourney) {
      (['explore', 'title', 'hotels', 'food', 'plan', 'publish'] as StepId[]).forEach(
        (s) => locked.add(s),
      );
    }
    if (!planReady) locked.add('publish');
    return locked;
  }, [canContinueJourney, planReady]);

  return (
    <div className="app-shell">
      <OfflineIndicator />
      <NavBar
        step={step}
        onStep={setStep}
        completedSteps={completedSteps}
        onNewPlan={() => setShowNewModal(true)}
        lockedSteps={lockedSteps}
      />

      <main
        className={`main-content${
          step === 'welcome' || step === 'journey' || step === 'plan' || step === 'explore'
            ? ' wide'
            : ''
        }`}
      >
        {step === 'welcome' && (
          <WelcomeStep
            trip={trip}
            onChange={updateTrip}
            onContinue={() => setStep('journey')}
          />
        )}
        {step === 'journey' && (
          <JourneyStep
            trip={trip}
            onChange={updateTrip}
            onLoadJapanPlan={loadJapanTemplate}
          />
        )}
        {step === 'explore' && <ExploreStep trip={trip} onChange={updateTrip} />}
        {step === 'title' && <TitleStep trip={trip} onChange={updateTrip} />}
        {step === 'hotels' && <HotelsStep trip={trip} onChange={updateTrip} />}
        {step === 'food' && <FoodStep trip={trip} onChange={updateTrip} />}
        {step === 'plan' && <PlanStep trip={trip} onChange={updateTrip} />}
        {step === 'publish' && (
          <PublishStep
            trip={trip}
            onExport={exportJson}
            onImport={importJson}
            username={username}
            onJumpToStep={(s) => setStep(s === 'calendar' ? 'journey' : s)}
          />
        )}
      </main>

      {step !== 'welcome' && (
      <div className="bottom-bar">
        <div className="bottom-bar-inner">
          {i > 0 ? (
            <button type="button" className="btn btn-secondary" onClick={goPrev}>
              {t('common.back')}
            </button>
          ) : (
            <span />
          )}
          {i < STEPS.length - 1 ? (
            <button
              type="button"
              className="btn btn-primary"
              onClick={goNext}
              disabled={
                (step === 'journey' && !canContinueJourney) ||
                (step === 'hotels' && !hotelsComplete(trip)) ||
                (step === 'plan' && !planReady)
              }
              title={
                step === 'journey' && !canContinueJourney
                  ? 'Nereden ve nereye alanlarını doldurun'
                  : step === 'hotels' && !hotelsComplete(trip)
                    ? 'Her otel için şehir, ad ve açık adres gerekli'
                    : step === 'plan' && !planReady
                      ? 'Önce "Gezi planı oluştur" ile günlük programı hazırlayın'
                      : undefined
              }
            >
              {t('common.continue')}
            </button>
          ) : (
            <a
              href={`/viewer/?u=${encodeURIComponent(username)}`}
              className="btn btn-primary"
              style={{ textDecoration: 'none', textAlign: 'center' }}
            >
              {t('nav.guide')}
            </a>
          )}
        </div>
      </div>
      )}

      <footer className="footer-minimal">
        <button type="button" className="btn-ghost" onClick={undo}>
          Geri al
        </button>
        <button type="button" className="btn-ghost" onClick={startWithJapanPlan}>
          🇯🇵 Japonya planını yükle
        </button>
        <a href="/">Klasik site</a>
      </footer>

      {showNewModal && (
        <div
          className="modal-backdrop"
          role="dialog"
          aria-modal="true"
          onClick={() => setShowNewModal(false)}
        >
          <div className="modal" ref={newModalRef} onClick={(e) => e.stopPropagation()}>
            <h3>Yeni plan</h3>
            <p>
              Japonya 14 günlük tam plan ile hızlı başlayabilir veya boş bir plandan
              kendi rotanı kurabilirsin.
            </p>
            <div className="modal-actions">
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() => setShowNewModal(false)}
              >
                Vazgeç
              </button>
              <button type="button" className="btn btn-secondary" onClick={confirmNewPlan}>
                Boş plan
              </button>
              <button type="button" className="btn btn-primary" onClick={startWithJapanPlan}>
                🇯🇵 Japonya planı
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
