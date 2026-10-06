import { useEffect, useRef } from "react";
import { Leaf } from "lucide-react";
import { useOptionalAuth } from "./auth";

// /login/ starts the sign-in inside the app, so the library stores the state and PKCE verifier
// that the callback checks. A hand-copied Cognito URL would sign in but fail at the callback.
export default function LoginPage() {
  const auth = useOptionalAuth();
  const started = useRef(false);
  useEffect(() => {
    if (!auth || auth.isLoading || auth.error || started.current) return;
    started.current = true;
    if (auth.isAuthenticated) window.location.replace("/");
    else auth.signinRedirect();
  }, [auth]);
  let message = "Taking you to sign-in…";
  if (!auth) message = "Sign-in is not configured for this build.";
  else if (auth.error) message = `Sign-in failed: ${auth.error.message}`;
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-5 px-6 text-center">
      <span className="rounded-xl bg-[#e8efde] p-3">
        <Leaf size={28} />
      </span>
      <p role="status" className="text-stone-600">
        {message}
      </p>
      <a href="/" className="text-sm font-medium text-[#536846] underline">
        Back to meetings
      </a>
    </main>
  );
}
