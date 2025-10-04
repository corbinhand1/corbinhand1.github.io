import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Vite configuration with React plugin and Tailwind via PostCSS.
export default defineConfig({
  plugins: [react()],
  base: './', // Essential for GitHub Pages deployment
  root: 'public', // Serve from public directory
  css: {
    postcss: {
      plugins: [require('tailwindcss'), require('autoprefixer')],
    },
  },
});