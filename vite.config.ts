import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Vite configuration with React plugin and Tailwind via PostCSS.
export default defineConfig({
  plugins: [react()],
  base: './', // Essential for GitHub Pages deployment
  css: {
    postcss: {
      plugins: [require('tailwindcss'), require('autoprefixer')],
    },
  },
});