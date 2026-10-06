import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { AuthProvider } from "react-oidc-context";
import App from "./App";
import LoginPage from "./LoginPage";
import { authEnabled, isLoginPage, oidcConfig } from "./auth";
import "./styles.css";
// CloudFront serves index.html for /login/ and /auth/callback/; the callback renders App while
// AuthProvider exchanges the code, then returns to /.
const page = isLoginPage() ? <LoginPage /> : <App />;
createRoot(document.getElementById("root")).render(
  <StrictMode>
    {authEnabled ? <AuthProvider {...oidcConfig}>{page}</AuthProvider> : page}
  </StrictMode>,
);
