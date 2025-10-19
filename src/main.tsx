import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './mobile-optimized.css?v=20241220-patrick-hand-fix';

// Create the root element and render the app in strict mode.
ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);