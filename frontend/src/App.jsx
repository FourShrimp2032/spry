import { useEffect, useRef, useState } from "react";
import {
  ArrowUpRight,
  CalendarDays,
  Check,
  Clock3,
  Leaf,
  LogIn,
  LogOut,
  Plus,
  RefreshCw,
  Users,
  X,
} from "lucide-react";
import { Button } from "./components/ui/button";
import { Card } from "./components/ui/card";
import { authEnabled, signOut, useOptionalAuth } from "./auth";
const API = (import.meta.env.VITE_API_URL || "http://localhost:8000").replace(
  /\/$/,
  "",
);
const date = (value, options) =>
  new Intl.DateTimeFormat(undefined, options).format(new Date(value));
const time = (value) => date(value, { hour: "2-digit", minute: "2-digit" });
const inputTime = (value) =>
  new Date(value.getTime() - value.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);

function Account({ auth }) {
  if (auth.isLoading)
    return <span className="text-xs text-stone-400">Checking sign-in…</span>;
  if (!auth.isAuthenticated)
    return (
      <Button size="sm" onClick={() => auth.signinRedirect()}>
        <LogIn size={15} /> Sign in
      </Button>
    );
  return (
    <div className="flex min-w-0 items-center gap-3">
      <span
        className="max-w-[45vw] truncate text-sm font-medium sm:max-w-[16rem]"
        title={auth.user.profile.email}
      >
        {auth.user.profile.email}
      </span>
      <Button variant="outline" size="sm" onClick={() => signOut(auth)}>
        <LogOut size={15} /> Sign out
      </Button>
    </div>
  );
}

export default function App() {
  const [meetings, setMeetings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const dialog = useRef(null);
  const createButton = useRef(null);
  const auth = useOptionalAuth();
  const token = auth?.user?.access_token;
  const authLoading = auth?.isLoading;
  // The API checks this token when it is protected (PROTECT_API=1); otherwise it ignores it.
  const authHeaders = token ? { Authorization: `Bearer ${token}` } : {};
  const signInMessage = "Sign in to see and create meetings.";
  async function load() {
    setLoading(true);
    setError("");
    try {
      const response = await fetch(`${API}/api/meetings`, {
        headers: authHeaders,
      });
      if (response.status === 401) throw new Error(signInMessage);
      if (!response.ok)
        throw new Error("Could not load meetings. Please try again.");
      setMeetings(await response.json());
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    // Wait for a stored session, so a signed-in user's first request carries the token.
    if (!authLoading) load();
  }, [authLoading, token]);
  useEffect(() => {
    if (showForm) dialog.current?.showModal();
    else dialog.current?.close();
  }, [showForm]);
  function closeForm() {
    setShowForm(false);
    createButton.current?.focus();
  }
  async function create(event) {
    event.preventDefault();
    setSaving(true);
    setError("");
    setNotice("");
    const form = new FormData(event.currentTarget);
    const body = {
      title: form.get("title").trim(),
      starts_at: new Date(form.get("starts_at")).toISOString(),
      ends_at: new Date(form.get("ends_at")).toISOString(),
      attendee_count: Number(form.get("attendee_count")),
    };
    if (!body.title || new Date(body.ends_at) <= new Date(body.starts_at)) {
      setError("Enter a title and an end time after the start time.");
      setSaving(false);
      return;
    }
    try {
      const response = await fetch(`${API}/api/meetings`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...authHeaders },
        body: JSON.stringify(body),
      });
      if (response.status === 401) throw new Error(signInMessage);
      if (!response.ok)
        throw new Error(
          response.status === 422
            ? "Check the meeting details and try again."
            : "Could not save the meeting. Please try again.",
        );
      const saved = await response.json();
      setMeetings((previous) =>
        [...previous, saved].sort(
          (a, b) =>
            a.starts_at.localeCompare(b.starts_at) || a.id.localeCompare(b.id),
        ),
      );
      closeForm();
      setNotice("Meeting created and saved.");
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  }
  const now = new Date();
  const upcoming = meetings.filter((m) => new Date(m.starts_at) >= now).length;
  const minutes = meetings.reduce(
    (total, m) => total + (new Date(m.ends_at) - new Date(m.starts_at)) / 60000,
    0,
  );
  const attendees = meetings.reduce((total, m) => total + m.attendee_count, 0);
  return (
    <div className="min-h-screen">
      <header className="border-b border-stone-200 bg-white px-6 lg:px-12">
        <div className="mx-auto flex h-20 max-w-7xl items-center justify-between">
          <a
            href="/"
            aria-label="Spry home"
            className="flex items-center gap-2 text-3xl font-bold tracking-tight"
          >
            <span className="rounded-xl bg-[#e8efde] p-2">
              <Leaf size={25} />
            </span>
            spry<span className="text-[#95ac78]">.</span>
          </a>
          <span className="hidden rounded-full bg-[#edf2e8] px-4 py-2 text-xs font-medium text-[#536846] sm:block">
            A little more clarity. A lot less meeting.
          </span>
          {authEnabled ? (
            <Account auth={auth} />
          ) : (
            <span className="flex h-10 w-10 items-center justify-center rounded-full border border-stone-200 bg-stone-50 text-xs font-semibold">
              SY
            </span>
          )}
        </div>
      </header>
      {auth?.error && (
        <p
          role="alert"
          className="mx-auto mt-6 max-w-7xl rounded-xl bg-red-50 p-4 text-sm text-red-800"
        >
          Sign-in failed: {auth.error.message}. Please try again.
        </p>
      )}
      <div className="mx-auto max-w-7xl px-6 py-10 lg:px-12 lg:py-14">
        <div className="mb-8 flex items-center gap-2 text-xs font-semibold uppercase tracking-[.18em] text-stone-500">
          <span className="h-2 w-2 rounded-full bg-[#86a666]" /> Your workspace{" "}
          <span className="mx-2 text-stone-300">/</span> Meetings
        </div>
        <div className="mb-10 flex flex-wrap items-end justify-between gap-5">
          <div>
            <h1 className="text-4xl font-semibold tracking-tight lg:text-5xl">
              Make time for what matters.
            </h1>
            <p className="mt-4 text-stone-500">
              Your meetings, in one calm place. Plan ahead and keep everyone in
              sync.
            </p>
          </div>
          <Button
            ref={createButton}
            onClick={() => {
              setError("");
              setShowForm(true);
            }}
          >
            <Plus size={17} /> New meeting
          </Button>
        </div>
        <section
          aria-label="Meeting overview"
          className="mb-10 grid gap-4 sm:grid-cols-3"
        >
          {[
            {
              label: "Meetings planned",
              value: meetings.length,
              note: `${upcoming} upcoming`,
              icon: CalendarDays,
            },
            {
              label: "Time together",
              value: `${(minutes / 60).toFixed(1)} h`,
              note: "Across all scheduled meetings",
              icon: Clock3,
            },
            {
              label: "Attendee places",
              value: attendees,
              note: "Total across all meetings",
              icon: Users,
            },
          ].map(({ label, value, note, icon: Icon }) => (
            <Card key={label} className="p-6">
              <div className="flex items-center justify-between text-sm text-stone-500">
                {label}
                <Icon size={18} className="text-[#75846b]" />
              </div>
              <p className="my-4 text-4xl font-semibold tracking-tight">
                {loading ? "—" : value}
              </p>
              <p className="text-xs text-stone-500">{note}</p>
            </Card>
          ))}
        </section>
        <div className="mb-5 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <h2 className="text-xl font-semibold">All meetings</h2>
            <span className="rounded-full bg-stone-200/60 px-2.5 py-1 text-xs">
              {meetings.length}
            </span>
          </div>
          <Button variant="outline" size="sm" onClick={load} disabled={loading}>
            <RefreshCw size={14} className={loading ? "animate-spin" : ""} />{" "}
            Refresh
          </Button>
        </div>
        {notice && (
          <p
            role="status"
            className="mb-4 flex items-center gap-2 text-sm text-green-800"
          >
            <Check size={16} />
            {notice}
          </p>
        )}
        {error && !showForm && (
          <p
            role="alert"
            className="mb-4 rounded-xl bg-red-50 p-4 text-sm text-red-800"
          >
            {error}
          </p>
        )}
        <Card className="overflow-hidden">
          <div className="hidden grid-cols-[1fr_180px_155px_110px] gap-4 border-b border-stone-100 bg-[#fafbf8] px-6 py-4 text-xs font-medium uppercase tracking-wider text-stone-500 md:grid">
            <span>Meeting</span>
            <span>Date</span>
            <span>Time</span>
            <span>Attendees</span>
          </div>
          {loading && (
            <p role="status" className="p-12 text-center text-stone-500">
              Loading your meetings…
            </p>
          )}
          {!loading && meetings.length === 0 && (
            <div className="p-14 text-center">
              <CalendarDays className="mx-auto mb-4 text-[#899b78]" size={32} />
              <h3 className="font-semibold">A fresh start for your calendar</h3>
              <p className="mt-2 text-sm text-stone-500">
                Create your first meeting to bring the team together.
              </p>
            </div>
          )}
          {!loading &&
            meetings.map((meeting, index) => (
              <article
                key={meeting.id}
                className="grid items-center gap-4 border-b border-stone-100 px-6 py-6 last:border-0 md:grid-cols-[1fr_180px_155px_110px]"
              >
                <div className="flex items-center gap-4">
                  <span
                    className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${index % 2 ? "bg-[#eeeaf5] text-[#8972a4]" : "bg-[#eef2e4] text-[#71854d]"}`}
                  >
                    <CalendarDays size={20} />
                  </span>
                  <div className="min-w-0">
                    <h3 className="break-words font-semibold">
                      {meeting.title}
                    </h3>
                    <p className="mt-1 text-xs text-stone-400">
                      {Math.round(
                        (new Date(meeting.ends_at) -
                          new Date(meeting.starts_at)) /
                          60000,
                      )}{" "}
                      minute meeting
                    </p>
                  </div>
                </div>
                <p className="text-sm text-stone-600">
                  {date(meeting.starts_at, {
                    month: "short",
                    day: "numeric",
                    year: "numeric",
                  })}
                </p>
                <p className="text-sm text-stone-600">
                  {time(meeting.starts_at)} – {time(meeting.ends_at)}
                </p>
                <p className="flex items-center gap-2 text-sm text-stone-600">
                  <Users size={15} />
                  {meeting.attendee_count}
                </p>
              </article>
            ))}
        </Card>
        <p className="mt-4 text-xs text-stone-400">
          Times shown in your local timezone ·{" "}
          {Intl.DateTimeFormat().resolvedOptions().timeZone}
        </p>
        <div className="mt-10 flex items-center justify-between rounded-2xl bg-[#eaf0e2] px-7 py-6">
          <div>
            <p className="font-medium text-[#425b37]">
              Good meetings start with a little intention.
            </p>
            <p className="mt-1 text-sm text-[#76856c]">
              A clear title. The right people. Just enough time.
            </p>
          </div>
          <ArrowUpRight className="hidden text-[#6f845c] sm:block" />
        </div>
        <footer className="mt-12 flex justify-between text-xs text-stone-400">
          <span>Spry · Make space for better work.</span>
          <span>Meetings workspace</span>
        </footer>
      </div>
      <dialog
        ref={dialog}
        onCancel={(event) => {
          event.preventDefault();
          if (!saving) closeForm();
        }}
        className="w-[min(92vw,500px)] rounded-2xl border border-stone-200 p-7 shadow-xl backdrop:bg-black/30"
        aria-labelledby="form-title"
      >
        {showForm && (
          <form onSubmit={create}>
            <div className="mb-6 flex items-center justify-between">
              <h2 id="form-title" className="text-2xl font-semibold">
                New meeting
              </h2>
              <button
                type="button"
                aria-label="Close"
                onClick={closeForm}
                disabled={saving}
              >
                <X size={20} />
              </button>
            </div>
            <div className="space-y-5">
              <label className="block">
                Meeting title
                <input
                  name="title"
                  required
                  maxLength={200}
                  placeholder="e.g. Weekly product sync"
                  autoFocus
                />
              </label>
              <label className="block">
                Starts at
                <input
                  type="datetime-local"
                  name="starts_at"
                  required
                  defaultValue={inputTime(new Date(Date.now() + 3600000))}
                />
              </label>
              <label className="block">
                Ends at
                <input
                  type="datetime-local"
                  name="ends_at"
                  required
                  defaultValue={inputTime(new Date(Date.now() + 7200000))}
                />
              </label>
              <label className="block">
                Attendee count
                <input
                  type="number"
                  name="attendee_count"
                  required
                  min="0"
                  step="1"
                  defaultValue="2"
                />
              </label>
            </div>
            {error && (
              <p role="alert" className="mt-4 text-sm text-red-700">
                {error}
              </p>
            )}
            <div className="mt-7 flex justify-end gap-3">
              <Button
                variant="outline"
                type="button"
                onClick={closeForm}
                disabled={saving}
              >
                Cancel
              </Button>
              <Button disabled={saving}>
                {saving ? "Saving…" : "Create meeting"}
              </Button>
            </div>
          </form>
        )}
      </dialog>
    </div>
  );
}
