/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './index.html',
    './src/**/*.{js,jsx,ts,tsx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        'handwritten': ['Patrick Hand', 'Bradley Hand', 'Brush Script MT', 'Comic Sans MS', 'Marker Felt', 'Kalam', 'Indie Flower', 'cursive'],
        'system': ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Text', 'Segoe UI', 'Roboto', 'sans-serif'],
      },
      fontSize: {
        'mobile-xs': 'clamp(9px, 2.5vw, 10px)',
        'mobile-sm': 'clamp(10px, 3vw, 12px)',
        'mobile-base': 'clamp(12px, 3.5vw, 14px)',
        'mobile-lg': 'clamp(14px, 4vw, 16px)',
        'mobile-xl': 'clamp(16px, 4.5vw, 18px)',
        'mobile-2xl': 'clamp(18px, 5vw, 22px)',
      },
      spacing: {
        'mobile-xs': '4px',
        'mobile-sm': '8px',
        'mobile-md': '12px',
        'mobile-lg': '16px',
        'mobile-xl': '20px',
      },
      width: {
        'stage-mobile': '160px',
        'stage-tablet': '200px',
        'stage-desktop': '240px',
      },
      backdropBlur: {
        'glass': '40px',
      },
      backgroundColor: {
        'glass': 'rgba(255, 255, 255, 0.1)',
        'glass-light': 'rgba(255, 255, 255, 0.05)',
      },
      borderColor: {
        'glass': 'rgba(255, 255, 255, 0.3)',
        'glass-light': 'rgba(255, 255, 255, 0.15)',
      },
    },
  },
  plugins: [],
};