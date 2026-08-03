import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';

/** Network durumu değişince üstte küçük banner gösterir.
 *  Offline → kırmızı uyarı; online'a dönüş → 2 sn yeşil onay. */
export function OfflineIndicator() {
  const { t } = useTranslation();
  const [online, setOnline] = useState<boolean>(
    typeof navigator !== 'undefined' ? navigator.onLine : true,
  );
  const [justBackOnline, setJustBackOnline] = useState(false);

  useEffect(() => {
    const handleOnline = () => {
      setOnline(true);
      setJustBackOnline(true);
      window.setTimeout(() => setJustBackOnline(false), 2000);
    };
    const handleOffline = () => setOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  if (online && !justBackOnline) return null;

  return (
    <div
      className={`offline-indicator ${online ? 'is-back' : 'is-offline'}`}
      role="status"
      aria-live="polite"
    >
      {online ? t('errors.backOnline') : t('errors.offline')}
    </div>
  );
}
