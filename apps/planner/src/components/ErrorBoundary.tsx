import { Component, type ErrorInfo, type ReactNode } from 'react';
import { i18n } from '../i18n';

interface Props {
  children: ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('[ErrorBoundary]', error, info.componentStack);
  }

  reset = () => {
    this.setState({ error: null });
  };

  reload = () => {
    window.location.reload();
  };

  render() {
    if (!this.state.error) return this.props.children;
    const t = i18n.t.bind(i18n);
    return (
      <div className="error-boundary">
        <div className="error-boundary-icon">⚠️</div>
        <h2>{t('errors.boundaryTitle')}</h2>
        <p>{t('errors.boundaryBody')}</p>
        <pre className="error-boundary-trace">
          {this.state.error.name}: {this.state.error.message}
        </pre>
        <div className="error-boundary-actions">
          <button type="button" className="btn btn-primary" onClick={this.reload}>
            {t('errors.reload')}
          </button>
          <button type="button" className="btn btn-secondary" onClick={this.reset}>
            {t('errors.retry')}
          </button>
        </div>
      </div>
    );
  }
}
