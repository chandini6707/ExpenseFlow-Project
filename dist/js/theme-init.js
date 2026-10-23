// Run before styles on every page to avoid a light flash during navigation.
(() => {
  let saved;
  try { saved = localStorage.getItem('expenseflow-theme'); } catch { /* Storage may be disabled. */ }
  document.documentElement.dataset.theme = saved === 'dark' || (saved !== 'light' && window.matchMedia?.('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
})();
