// Tarayıcı bildirimleri (Web Notifications API). Bir nokta GPS ile otomatik
// "gezildi" olduğunda kullanıcıya bildirim gönderir.

export function notificationsSupported(): boolean {
  return typeof window !== 'undefined' && 'Notification' in window;
}

/** Kullanıcı jesti içinde çağrılmalı (izin penceresi için). */
export function ensureNotificationPermission(): void {
  if (!notificationsSupported()) return;
  if (Notification.permission === 'default') {
    Notification.requestPermission().catch(() => {
      /* yok say */
    });
  }
}

/** İzin verildiyse bir bildirim gösterir; yoksa sessizce çıkar. */
export function notifyVisit(title: string, body: string): void {
  if (!notificationsSupported()) return;
  if (Notification.permission !== 'granted') return;
  try {
    new Notification(title, { body, icon: '/viewer/favicon.svg', tag: 'visit' });
  } catch {
    /* bazı tarayıcılar SW olmadan engelleyebilir */
  }
}
