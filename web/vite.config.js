import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Build output goes next to the manifest: ui_page 'ui/index.html'.
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  base: './',
  build: {
    outDir: '../ui',
    emptyOutDir: true,
    assetsDir: 'assets',
  },
})
