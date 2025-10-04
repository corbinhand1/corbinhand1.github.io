import React from 'react';
import ReactDOM from 'react-dom/client';
import TestApp from './TestApp';
import './styles.css';

// Create the root element and render the app in strict mode.
ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <TestApp />
  </React.StrictMode>,
);