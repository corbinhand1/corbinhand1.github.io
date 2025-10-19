import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'path';

// Professional Vite configuration with proper dev/prod separation
export default defineConfig(({ command, mode }) => {
  const isDev = command === 'serve';
  const isProd = command === 'build';
  
  return {
    plugins: [react()],
    
    // Base path: root for dev, relative for production (GitHub Pages)
    base: isDev ? '/' : './',
    
    // Development server configuration
    server: {
      port: 5173,
      host: true,
      open: true,
      strictPort: false, // Allow port fallback for better UX
    },
    
    // Build configuration
    build: {
      outDir: 'dist',
      assetsDir: 'assets',
      sourcemap: false,
      minify: 'terser',
      rollupOptions: {
        input: {
          main: resolve(__dirname, 'index.html'),
        },
        output: {
          assetFileNames: (assetInfo) => {
            if (assetInfo.name && assetInfo.name.endsWith('.js')) {
              return 'assets/[name]-[hash][extname]';
            }
            return 'assets/[name]-[hash][extname]';
          },
        },
      },
    },
    
    // CSS configuration
    css: {
      postcss: {
        plugins: [
          require('tailwindcss'),
          require('autoprefixer'),
        ],
      },
    },
    
    // Environment variables
    define: {
      __DEV__: isDev,
      __PROD__: isProd,
    },
    
    // Optimize dependencies
    optimizeDeps: {
      include: ['react', 'react-dom', 'framer-motion', 'canvas-confetti'],
    },
  };
});