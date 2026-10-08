<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    title,
    description = '',
    children
  }: { title: string; description?: string; children: Snippet } = $props();
</script>

<section class="tab-panel" aria-label={title}>
  <h2 class="tab-heading">{title}</h2>
  {#if description}
    <p class="tab-description">{description}</p>
  {/if}
  {@render children()}
</section>
