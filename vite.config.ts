import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'path';

// Professional Vite configuration with proper dev/prod separation
export default defineConfig(({ command, mode }) => {
  const isDev = command === 'serve';
  const isProd = command === 'build';
  
  return {
    plugins: [
      react(),
      // The root index.html is the DEPLOYED (built) page, because `npm run deploy`
      // copies dist/* over the repo root. The real source entry is src-index.html.
      // Emit it as index.html so the deploy copy lands in the right place.
      {
        name: 'emit-src-index-as-index',
        enforce: 'post',
        generateBundle(_opts, bundle) {
          const entry = bundle['src-index.html'];
          if (entry) {
            delete bundle['src-index.html'];
            entry.fileName = 'index.html';
            bundle['index.html'] = entry;
          }
        },
      },
    ],
    
    // Base path: root for dev, relative for production (GitHub Pages)
    base: isDev ? '/' : './',
    
    // Development server configuration
    server: {
      port: 5173,
      host: true,
      open: '/src-index.html',
      strictPort: false, // Allow port fallback for better UX
    },
    
    // Do NOT copy public/ into dist. public/cuetocue holds a stale copy of the
    // Cue to Cue viewer, and deploying it would overwrite the live /cuetocue/
    // (which the Cue to Cue Mac app publishes to directly).
    publicDir: false,

    // Build configuration
    build: {
      outDir: 'dist',
      assetsDir: 'assets',
      sourcemap: false,
      minify: 'terser',
      rollupOptions: {
        input: {
          main: resolve(__dirname, 'src-index.html'),
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