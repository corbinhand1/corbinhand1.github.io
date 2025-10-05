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
      },
    },
  },
  plugins: [],
};