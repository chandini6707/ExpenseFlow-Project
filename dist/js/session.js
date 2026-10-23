import { db, configured, getConfig } from './api.js';

// Theme and public connection settings are preferences, never session credentials.
export function isSessionKey(key, authKey) {
  return key === authKey || key.startsWith(authKey + '-') || key.startsWith(authKey + '.') || /^expenseflow[-_](demo|session|user|role|oauth-role)([-_]|$)/i.test(key) || /^demo(Session|User|Role|Token)$/i.test(key);
}
export function clearApplicationSession() {
  const ref = new URL(getConfig().supabaseUrl).hostname.split('.')[0];
  const authKey = `sb-${ref}-auth-token`;
  for (const name of ['localStorage', 'sessionStorage']) {
    try { const storage=window[name];for (const key of Object.keys(storage)) if (isSessionKey(key, authKey)) storage.removeItem(key); } catch { /* Restricted storage. */ }
  }
  // Expire historical demo cookies on this site's paths, including root/domain cookies.
  const paths = [...new Set(['/', location.pathname.replace(/[^/]*$/, '')])];
  for (const entry of document.cookie.split(';')) {
    const name = entry.trim().split('=')[0];
    if (!isSessionKey(name, authKey)) continue;
    for (const path of paths) for (const domain of ['', `; Domain=${location.hostname}`]) document.cookie = `${name}=; Max-Age=0; Path=${path}${domain}; SameSite=Lax`;
  }
}
export function hasUnsavedChanges() { return !!document.querySelector('form[data-dirty="true"]'); }
export async function signOut() {
  if (hasUnsavedChanges() && !window.confirm('You have unsaved changes. Discard them and sign out?')) return false;
  // Demo accounts in this project are real Supabase users and follow the same flow.
  if (configured()) {
    const { error } = await db().auth.signOut({ scope: 'local' });
    if (error) throw new Error('Could not sign out securely. Check your connection and try again.');
  }
  clearApplicationSession();
  document.querySelector('#app')?.replaceChildren();
  location.replace('login.html');
  return true;
}
export async function authenticatedUser() {
  const { data: local, error: localError } = await db().auth.getSession();
  if (localError) throw localError;
  if (!local.session) return null;
  const { data, error } = await db().auth.getUser();
  if (error) {
    if ([401, 403].includes(error.status) || error.name === 'AuthSessionMissingError') {
      await db().auth.signOut({ scope: 'local' });
      clearApplicationSession();
      return null;
    }
    throw new Error('Your session could not be verified. Check your connection and reload.');
  }
  return data.user;
}
