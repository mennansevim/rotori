import { Component, type ErrorInfo, type ReactNode } from 'react';

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
    return (
      <div className="error-boundary">
        <div className="error-boundary-icon">⚠️</div>
        <h2>Bir şeyler ters gitti</h2>
        <p>
          Uygulamada beklenmedik bir hata oluştu. Sayfayı yenilemeyi deneyebilirsin —
          planın <code>localStorage</code>'da güvende.
        </p>
        <pre className="error-boundary-trace">
          {this.state.error.name}: {this.state.error.message}
        </pre>
        <div className="error-boundary-actions">
          <button type="button" className="btn btn-primary" onClick={this.reload}>
            Sayfayı yenile
          </button>
          <button type="button" className="btn btn-secondary" onClick={this.reset}>
            Tekrar dene
          </button>
        </div>
      </div>
    );
  }
}
