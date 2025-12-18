import React from 'react';
import NebulaShowtime from './components/NebulaShowtime';

/**
 * The root application component. It simply renders the NebulaShowtime
 * component centered on the page. You can add additional global
 * layout or context providers here if necessary.
 */
const App: React.FC = () => {
  return (
    <div className="min-h-screen flex flex-col items-center justify-start px-4">
      <NebulaShowtime />
    </div>
  );
};

export default App;