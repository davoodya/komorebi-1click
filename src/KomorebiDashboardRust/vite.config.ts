import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import tailwindcss from '@tailwindcss/vite';

// Tauri drives the dev server through `devUrl` (tauri.conf.json) and reads the
// production bundles from `frontendDist`. Both must stay in lockstep with the
// ports and paths declared there.
export default defineConfig({
  plugins: [svelte(), tailwindcss()],
  clearScreen: false,
  server: {
    // Static port: the Tauri dev URL hard-codes it, and a stray second server
    // must fail loudly rather than silently bind a different port.
    port: 1420,
    strictPort: true,
    host: false,
    watch: { ignored: ['**/src-tauri/**'] }
  },
  build: {
    // WebView2 on the target machines is Chromium 110+; no polyfill debt.
    target: 'chrome110',
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: false,
    chunkSizeWarningLimit: 1200
  },
  test: {
    environment: 'jsdom',
    include: ['src/tests/**/*.spec.ts'],
    restoreMocks: true
  }
});
