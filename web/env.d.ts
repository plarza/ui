declare module '*.svg?raw' {
  const content: string;
  export default content;
}
// For tsc, which can't read .svelte files; svelte-check checks the component itself.
declare module '*.svelte' {
  import type { Component } from 'svelte';
  const component: Component<any>;
  export default component;
}
