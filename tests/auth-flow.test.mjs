import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fetchAuthSettings, googleSignInURL, registerWithoutConfirmation, readOAuthFailure, GOOGLE_DISABLED, CONFIRMATION_ENABLED } from '../dist/js/auth-flow.js';
import { friendlyError } from '../dist/js/utils.js';

const config = { supabaseUrl: 'https://project.supabase.co', supabaseKey: 'sb_publishable_test_public_key_only' };
const site = 'https://expenseflow.example/login.html';
const credentials = { email: 'employee@example.com', password: 'example-password', fullName: 'Example Employee', role: 'admin' };
const settings = { external: { google: true, email: true }, mailer_autoconfirm: true, disable_signup: false };
const respond = overrides => async () => ({ ok: true, json: async () => ({ ...settings, ...overrides }) });

test('Disabled Google provider does not start an OAuth redirect', async () => {
  let called = false;
  const client = { auth: { signInWithOAuth: async () => { called = true; } } };
  await assert.rejects(googleSignInURL(client, config, site, respond({ external: { google: false, email: true } })), { message: GOOGLE_DISABLED });
  assert.equal(called, false);
});

test('Enabled Google provider uses the login callback and waits for explicit navigation', async () => {
  let captured;
  const client = { auth: { signInWithOAuth: async options => {
    captured = options;
    return { data: { url: config.supabaseUrl + '/auth/v1/authorize?provider=google' }, error: null };
  } } };
  assert.equal(await googleSignInURL(client, config, site + '?old=1#old', respond()), config.supabaseUrl + '/auth/v1/authorize?provider=google');
  assert.deepEqual(captured, { provider: 'google', options: { redirectTo: site, skipBrowserRedirect: true } });
});

test('An unexpected OAuth navigation target is rejected', async () => {
  const client = { auth: { signInWithOAuth: async () => ({ data: { url: 'https://other.example/auth/v1/authorize' } }) } };
  await assert.rejects(googleSignInURL(client, config, site, respond()), /could not start/);
});

test('Registration never requests a confirmation email when server confirmation is enabled', async () => {
  let called = false;
  const client = { auth: { signUp: async () => { called = true; } } };
  await assert.rejects(registerWithoutConfirmation(client, config, credentials, respond({ mailer_autoconfirm: false })), { message: CONFIRMATION_ENABLED });
  assert.equal(called, false);
});

test('Registration with confirmation disabled returns a real Supabase session and sends only employee metadata', async () => {
  let captured;
  const response = { session: { user: { id: 'user-1' } }, user: { id: 'user-1' } };
  const client = { auth: { signUp: async payload => { captured = payload; return { data: response, error: null }; } } };
  assert.equal(await registerWithoutConfirmation(client, config, credentials, respond()), response);
  assert.deepEqual(captured, { email: credentials.email, password: credentials.password, options: { data: { full_name: credentials.fullName, requested_role: 'employee' } } });
});

test('Registration cannot manufacture a session after an incomplete signup', async () => {
  const client = { auth: { signUp: async () => ({ data: { user: { id: 'user-1' }, session: null } }) } };
  await assert.rejects(registerWithoutConfirmation(client, config, credentials, respond()), /activation did not complete/);
});

test('Disabled registrations and network failures do not create an account', async () => {
  let called = false;
  const client = { auth: { signUp: async () => { called = true; } } };
  await assert.rejects(registerWithoutConfirmation(client, config, credentials, respond({ disable_signup: true })), /registrations are currently disabled/);
  await assert.rejects(registerWithoutConfirmation(client, config, credentials, async () => { throw new TypeError('Failed to fetch'); }), /Failed to fetch/);
  assert.equal(called, false);
});

test('Settings requests use the public API key and never forward browser cookies', async () => {
  let url, options;
  await fetchAuthSettings(config, async (u, o) => { url = u; options = o; return { ok: true, json: async () => settings }; });
  assert.equal(url, config.supabaseUrl + '/auth/v1/settings');
  assert.deepEqual(options.headers, { apikey: config.supabaseKey });
  assert.equal(options.credentials, 'omit');
  assert.equal(options.cache, 'no-store');
  await assert.rejects(fetchAuthSettings(config, async () => ({ ok: false })), /could not be loaded/);
  await assert.rejects(fetchAuthSettings(config, async () => ({ ok: true, json: async () => ({}) })), /incomplete/);
});

test('Callback failures show useful messages without reflecting provider input', () => {
  const cancelled = readOAuthFailure(site + '?keep=1&error=access_denied&error_description=%3Cscript%3E');
  assert.match(cancelled.message, /cancelled or access was denied/);
  assert.equal(cancelled.cleanURL, site + '?keep=1');
  assert.ok(!cancelled.message.includes('<script>'));
  const failure = readOAuthFailure(site + '#error=server_error&error_code=flow_state_expired');
  assert.match(failure.message, /expired or was opened in another browser/);
  assert.equal(failure.cleanURL, site);
  assert.match(readOAuthFailure(site + '?error=redirect_uri_mismatch').message, /redirect is not configured correctly/);
  assert.match(readOAuthFailure(site + '?error=invalid_client').message, /replace the Google Client ID and its matching Client Secret/);
});

test('Successful PKCE callbacks are left intact for the Supabase SDK', () => {
  assert.equal(readOAuthFailure(site + '?code=example-pkce-code'), null);
  assert.equal(readOAuthFailure(site), null);
});

test('Existing unconfirmed accounts receive activation guidance rather than a missing-email loop', () => {
  assert.match(friendlyError(new Error('Email not confirmed')), /administrator activation/);
});
