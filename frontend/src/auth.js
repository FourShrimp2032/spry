import { useAuth } from "react-oidc-context";
// Build-time values from the auth stack's outputs (make deploy-frontend / make auth-env).
const authority = import.meta.env.VITE_COGNITO_AUTHORITY;
const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID;
const loginDomain = import.meta.env.VITE_COGNITO_DOMAIN;
export const authEnabled = Boolean(authority && clientId && loginDomain);
// Cognito matches these exactly, trailing slash included (see infra/auth.yml).
const callbackUrl = () => `${window.location.origin}/auth/callback/`;
const homeUrl = () => `${window.location.origin}/`;

export const oidcConfig = {
  authority,
  client_id: clientId,
  redirect_uri: callbackUrl(),
  scope: "openid email profile",
  // Drop ?code=&state= and the callback path once the tokens are stored.
  onSigninCallback: () => window.history.replaceState({}, document.title, "/"),
};

// authEnabled is fixed at build time, so every render calls the same hooks.
export const useOptionalAuth = authEnabled ? useAuth : () => null;

export const isLoginPage = () =>
  window.location.pathname.replace(/\/+$/, "") === "/login";

export async function signOut(auth) {
  await auth.removeUser();
  // Cognito has no OIDC end-session endpoint; its /logout ends the managed login session.
  const query = new URLSearchParams({
    client_id: clientId,
    logout_uri: homeUrl(),
  });
  window.location.assign(`${loginDomain}/logout?${query}`);
}
