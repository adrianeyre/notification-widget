import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// SITE_VERSION (optional) is the app version shown in the footer, e.g. "0.3.0".
// Served from the root of a custom domain, so base stays "/".
export default defineConfig({
  plugins: [react()],
  base: '/',
  define: {
    __SITE_VERSION__: JSON.stringify(process.env.SITE_VERSION ?? ''),
  },
  build: { target: 'es2022', outDir: 'dist', emptyOutDir: true },
  server: { host: '127.0.0.1' },
})
