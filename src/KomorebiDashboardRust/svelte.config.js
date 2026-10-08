import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

export default {
  // TypeScript inside .svelte files is compiled by Vite; this keeps
  // `svelte-check` compiling the same way the build does.
  preprocess: vitePreprocess()
};
