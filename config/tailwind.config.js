console.log("✅ Tailwind config loaded");

const defaultTheme = require('tailwindcss/defaultTheme');

module.exports = {
  content: [
    './app/views/**/*.html.erb',
    './app/components/**/*.html.erb',
    './app/javascript/**/*.js',
    './app/helpers/**/*.rb',
    './app/assets/stylesheets/**/*.css'
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      },
      colors: {
        prophet: {
          indigo: '#6627D3',
          pink: '#FB7185',
          cyan: '#06B6D4',
          black: '111827',
          seasalt: 'F8FAFC',
        },
        betting: { 
          green: '#059669',
          yellow: '#D97706',
          red: '#DC2626',
          blue: '#0284C7',
        },
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ],
};
