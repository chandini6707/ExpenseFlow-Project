import { requestedRole } from './access.js';
// These checks explain configuration errors; Supabase still enforces authentication.
export const GOOGLE_DISABLED = 'Google sign-in is not enabled for this workspace. Ask the workspace administrator to enable the Google provider in Supabase.';
export const CONFIRMATION_ENABLED = 'Immediate registration is not enabled yet. The workspace administrator must turn off Confirm email in Supabase Authentication → Sign In / Providers → Email. No registration request was sent.';

export async function fetchAuthSettings(config, request = fetch) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const response = await request(`${config.supabaseUrl.replace(/\/$/, '')}/auth/v1/settings`, {
      headers: { apikey: config.supabaseKey },
      cache: 'no-store',
      credentials: 'omit',
      signal: controller.signal
    });
    if (!response.ok) throw new Error('Authentication settings could not be loaded. Check the Supabase project URL and public key, then try again.');
    const settings = await response.json();
    if (!settings || typeof settings.external !== 'object' || !settings.external || typeof settings.mailer_autoconfirm !== 'boolean') {
      throw new Error('Supabase returned incomplete authentication settings. Please try again.');
    }
    return settings;
  } catch (error) {
    if (error.name === 'AbortError') throw new Error('Supabase is taking too long to respond. Please try again.');
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

export async function registerWithoutConfirmation(client, config, { email, password, fullName, requestedRole: roleRequest }, request = fetch) {
  const settings = await fetchAuthSettings(config, request);
  if (settings.disable_signup) throw new Error('New registrations are currently disabled. Contact your workspace administrator.');
  if (!settings.external.email) throw new Error('Email and password registration is not enabled for this workspace.');
  // Do not initiate an email-confirmation flow when this demo requires immediate access.
  if (!settings.mailer_autoconfirm) throw new Error(CONFIRMATION_ENABLED);
  const { data, error } = await client.auth.signUp({
    email, password, options: { data: { full_name: fullName, requested_role: requestedRole(roleRequest) } }
  });
  if (error) throw error;
  if (!data?.session || !data.user) {
    throw new Error('Account activation did not complete. Ask your workspace administrator to check email-confirmation settings, then try signing in.');
  }
  return data;
}

export async function googleSignInURL(client, config, currentURL, request = fetch) {
  const settings = await fetchAuthSettings(config, request);
  if (!settings.external.google) throw new Error(GOOGLE_DISABLED);
  const redirectTo = new URL('login.html', currentURL).href;
  const { data, error } = await client.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo, skipBrowserRedirect: true }
  });
  if (error) throw error;
  // Navigate only to the configured Supabase authorization endpoint.
  const url = new URL(data?.url || '', config.supabaseUrl);
  if (url.origin !== new URL(config.supabaseUrl).origin || url.pathname !== '/auth/v1/authorize') {
    throw new Error('Google sign-in could not start. Please try again.');
  }
  return url.href;
}

export function oauthFailureMessage(code = '', description = '') {
  const value = `${code} ${description}`;
  if (/provider.*(disabled|not enabled)|unsupported.provider/i.test(value)) return GOOGLE_DISABLED;
  if (/invalid_client|OAuth client was not found/i.test(value)) {
    return 'Google does not recognize the configured OAuth client. Ask your workspace administrator to replace the Google Client ID and its matching Client Secret in Supabase.';
  }
  if (/redirect_uri_mismatch|redirect.*(invalid|mismatch|not allowed)/i.test(value)) {
    return 'The Google sign-in redirect is not configured correctly. Ask your workspace administrator to check the Google callback and Supabase redirect URLs.';
  }
  if (/access_denied/i.test(code)) return 'Google sign-in was cancelled or access was denied. Try again and choose an account allowed by your organization.';
  if (/flow_state|code.verifier|pkce|expired/i.test(value)) return 'This sign-in link expired or was opened in another browser. Start Google sign-in again in this tab.';
  return 'Google sign-in could not be completed. Try again, or contact your workspace administrator if it continues.';
}

export function readOAuthFailure(currentURL) {
  const url = new URL(currentURL);
  const fragment = new URLSearchParams(url.hash.slice(1));
  const queryFailed = ['error', 'error_code', 'error_description'].some(key => url.searchParams.has(key));
  const hashFailed = ['error', 'error_code', 'error_description'].some(key => fragment.has(key));
  if (!queryFailed && !hashFailed) return null; // Keep successful PKCE codes for the SDK.
  const parameters = queryFailed ? url.searchParams : fragment;
  const message = oauthFailureMessage(parameters.get('error_code') || parameters.get('error') || '', parameters.get('error_description') || '');
  for (const key of ['error', 'error_code', 'error_description', 'error_uri']) url.searchParams.delete(key);
  if (hashFailed) url.hash = '';
  return { message, cleanURL: url.href };
}
