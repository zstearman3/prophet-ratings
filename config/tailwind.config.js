const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  safelist: [
    'bg-gray-900',
    'bg-red-900',
    'hover:bg-gray-800',
  ],
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}',
    './app/assets/stylesheets/**/*.css',
    './app/components/**/*.{html.erb,erb}',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ]
}
