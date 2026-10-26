import { useEffect, useRef, useState } from "react";
import { Plus, Sparkles, Trash2, X } from "lucide-react";
import { Button } from "./components/ui/button";

// The parser suggests; the main API saves. Empty when the AI stack is not deployed.
const PARSER_URL = (import.meta.env.VITE_PARSER_URL || "").replace(/\/$/, "");
const MAX_CHARS = 10000;
const blankItem = () => ({ topic: "", owner: "", minutes: "", suggested: {} });
const blankAction = () => ({ task: "", owner: "", due: "", suggested: {} });
// The user's "Monday" is in the user's time zone, not the Lambda function's (UTC).
const localToday = () => {
  const now = new Date();
  return new Date(now.getTime() - now.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 10);
};
const parseErrors = {
  401: "Sign in to use Paste an agenda.",
  413: `The text is too long. Paste at most ${MAX_CHARS.toLocaleString()} characters.`,
  422: "Could not find an agenda in this text. Type it below instead.",
  429: "The parser is busy right now. Try again in a minute, or type the agenda below.",
};

// Every field the model filled is marked until the user changes it.
function fromSuggestion(rows, fields, flagged, prefix) {
  return rows.map((row, index) => {
    const suggested = {};
    const values = {};
    for (const field of fields) {
      values[field] = row[field] ?? "";
      if (row[field] !== null && row[field] !== undefined)
        suggested[field] = flagged.has(`${prefix}.${index}.${field}`)
          ? "not in text"
          : "suggested";
    }
    return { ...values, suggested };
  });
}

function Badge({ kind }) {
  if (!kind) return null;
  const warning = kind === "not in text";
  return (
    <span
      className={`ml-2 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide ${warning ? "bg-amber-100 text-amber-800" : "bg-[#eef2e4] text-[#5b7340]"}`}
      title={
        warning
          ? "This name does not appear in the pasted text. Check it."
          : "Filled in by the AI. Check it."
      }
    >
      {!warning && <Sparkles size={10} />}
      {kind}
    </span>
  );
}

function Field({ label, kind, ...props }) {
  return (
    <label className="block min-w-0">
      <span className="flex items-center">
        {label}
        <Badge kind={kind} />
      </span>
      <input {...props} />
    </label>
  );
}

export default function AgendaDialog({
  meeting,
  authHeaders,
  signedIn,
  onClose,
  onSaved,
}) {
  const dialog = useRef(null);
  const request = useRef(null);
  const [text, setText] = useState("");
  const [parsing, setParsing] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [parseError, setParseError] = useState("");
  const [items, setItems] = useState(
    meeting.agenda?.items.map((i) => ({
      topic: i.topic,
      owner: i.owner ?? "",
      minutes: i.minutes ?? "",
      suggested: {},
    })) ?? [blankItem()],
  );
  const [actions, setActions] = useState(
    meeting.agenda?.action_items.map((a) => ({
      task: a.task,
      owner: a.owner ?? "",
      due: a.due ?? "",
      suggested: {},
    })) ?? [],
  );
  const [suggestion, setSuggestion] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    dialog.current?.showModal();
    return () => request.current?.abort();
  }, []);
  useEffect(() => {
    if (!parsing) return undefined;
    setSeconds(0);
    const timer = setInterval(() => setSeconds((s) => s + 1), 1000);
    return () => clearInterval(timer);
  }, [parsing]);

  async function parse() {
    setParseError("");
    if (text.length > MAX_CHARS) return setParseError(parseErrors[413]);
    const controller = new AbortController();
    request.current = controller;
    setParsing(true);
    try {
      const response = await fetch(PARSER_URL, {
        method: "POST",
        signal: controller.signal,
        headers: { "Content-Type": "application/json", ...authHeaders },
        body: JSON.stringify({
          text,
          today: localToday(),
          tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }),
      });
      if (!response.ok)
        throw new Error(
          parseErrors[response.status] ??
            "The parser is unavailable. Type the agenda below; everything else still works.",
        );
      const result = await response.json();
      const flagged = new Set(result.not_in_text);
      const parsed = result.agenda;
      setItems(
        parsed.items.length
          ? fromSuggestion(
              parsed.items,
              ["topic", "owner", "minutes"],
              flagged,
              "items",
            )
          : [blankItem()],
      );
      setActions(
        fromSuggestion(
          parsed.action_items,
          ["task", "owner", "due"],
          flagged,
          "action_items",
        ),
      );
      setSuggestion(result);
    } catch (e) {
      setParseError(
        e.name === "AbortError"
          ? "Parsing cancelled."
          : e instanceof TypeError
            ? "Network error. Check your connection and try again."
            : e.message,
      );
    } finally {
      setParsing(false);
      request.current = null;
    }
  }

  // Touching a field makes it the user's: the badge goes away.
  const update = (setRows) => (index, field, value) =>
    setRows((rows) =>
      rows.map((row, i) =>
        i === index
          ? {
              ...row,
              [field]: value,
              suggested: { ...row.suggested, [field]: undefined },
            }
          : row,
      ),
    );
  const updateItem = update(setItems);
  const updateAction = update(setActions);

  async function save(event) {
    event.preventDefault();
    setError("");
    const clean = (value) =>
      String(value).trim() ? String(value).trim() : null;
    const body = {
      items: items
        .filter((i) => i.topic.trim())
        .map((i) => ({
          topic: i.topic.trim(),
          owner: clean(i.owner),
          minutes: i.minutes === "" ? null : Number(i.minutes),
        })),
      action_items: actions
        .filter((a) => a.task.trim())
        .map((a) => ({
          task: a.task.trim(),
          owner: clean(a.owner),
          due: a.due || null,
        })),
      // What the model suggested, kept next to what the user saved.
      ai_suggestion: suggestion && {
        agenda: suggestion.agenda,
        model: suggestion.model,
        prompt_version: suggestion.prompt_version,
      },
    };
    if (!body.items.length) return setError("Add at least one agenda item.");
    setSaving(true);
    try {
      const response = await onSaved(body);
      if (response) onClose();
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  }

  const extras = suggestion && [
    suggestion.agenda.title && `title “${suggestion.agenda.title}”`,
    suggestion.agenda.starts_at &&
      `starts ${new Date(suggestion.agenda.starts_at).toLocaleString()}`,
    suggestion.agenda.duration_minutes &&
      `${suggestion.agenda.duration_minutes} min`,
  ];

  return (
    <dialog
      ref={dialog}
      onCancel={(event) => {
        event.preventDefault();
        if (!saving) onClose();
      }}
      className="w-[min(94vw,760px)] rounded-2xl border border-stone-200 p-0 shadow-xl backdrop:bg-black/30"
      aria-labelledby="agenda-title"
    >
      <form onSubmit={save} className="max-h-[88vh] overflow-y-auto p-7">
        <div className="mb-5 flex items-start justify-between gap-4">
          <div>
            <h2 id="agenda-title" className="text-2xl font-semibold">
              Agenda
            </h2>
            <p className="mt-1 text-sm text-stone-500">{meeting.title}</p>
          </div>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            disabled={saving}
          >
            <X size={20} />
          </button>
        </div>

        {PARSER_URL && (
          <section className="mb-6 rounded-xl bg-[#f3f6ef] p-4">
            <label className="block" htmlFor="paste">
              <span className="flex items-center gap-2">
                <Sparkles size={15} className="text-[#6f845c]" /> Paste an
                agenda
              </span>
            </label>
            <p className="mt-1 text-xs text-stone-500">
              An email, a chat message or notes. The AI fills in the form below;
              you check it and save.
            </p>
            <textarea
              id="paste"
              rows={5}
              value={text}
              onChange={(e) => setText(e.target.value)}
              disabled={parsing || !signedIn}
              placeholder="Пн 10:00, синк по прайсингу, 45 хв. 1) нові тарифи Pro — Олена, 15 хв 2) …"
            />
            <div className="mt-3 flex flex-wrap items-center gap-3">
              {parsing ? (
                <>
                  <span role="status" className="text-sm text-stone-600">
                    Reading your agenda… {seconds}s (usually 2–8 seconds)
                  </span>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => request.current?.abort()}
                  >
                    Cancel
                  </Button>
                </>
              ) : (
                <Button
                  type="button"
                  size="sm"
                  onClick={parse}
                  disabled={!text.trim() || !signedIn}
                >
                  <Sparkles size={14} /> Parse
                </Button>
              )}
              <span
                className={`ml-auto text-xs ${text.length > MAX_CHARS ? "text-red-700" : "text-stone-400"}`}
              >
                {text.length.toLocaleString()} / {MAX_CHARS.toLocaleString()}
              </span>
            </div>
            {!signedIn && (
              <p className="mt-2 text-sm text-stone-600">{parseErrors[401]}</p>
            )}
            {parseError && (
              <p role="alert" className="mt-2 text-sm text-red-700">
                {parseError}
              </p>
            )}
            {extras?.some(Boolean) && (
              <p className="mt-2 text-xs text-stone-500">
                The text also mentions: {extras.filter(Boolean).join(" · ")}
              </p>
            )}
          </section>
        )}

        <h3 className="mb-3 font-semibold">Items</h3>
        <div className="space-y-3">
          {items.map((item, index) => (
            <div
              key={index}
              className="grid grid-cols-[1fr_auto] gap-3 sm:grid-cols-[2fr_1fr_90px_auto]"
            >
              <Field
                label="Topic"
                kind={item.suggested.topic}
                value={item.topic}
                maxLength={300}
                onChange={(e) => updateItem(index, "topic", e.target.value)}
              />
              <Field
                label="Owner"
                kind={item.suggested.owner}
                value={item.owner}
                maxLength={200}
                onChange={(e) => updateItem(index, "owner", e.target.value)}
              />
              <Field
                label="Min"
                kind={item.suggested.minutes && "AI"}
                type="number"
                min="1"
                max="480"
                value={item.minutes}
                onChange={(e) => updateItem(index, "minutes", e.target.value)}
              />
              <button
                type="button"
                aria-label={`Remove item ${index + 1}`}
                className="mt-6 self-center text-stone-400 hover:text-red-700"
                onClick={() =>
                  setItems((rows) => rows.filter((_, i) => i !== index))
                }
              >
                <Trash2 size={16} />
              </button>
            </div>
          ))}
        </div>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="mt-3"
          onClick={() => setItems((rows) => [...rows, blankItem()])}
        >
          <Plus size={14} /> Add item
        </Button>

        <h3 className="mb-3 mt-7 font-semibold">Action items</h3>
        {actions.length === 0 && (
          <p className="text-sm text-stone-500">No action items.</p>
        )}
        <div className="space-y-3">
          {actions.map((action, index) => (
            <div
              key={index}
              className="grid grid-cols-[1fr_auto] gap-3 sm:grid-cols-[2fr_1fr_150px_auto]"
            >
              <Field
                label="Task"
                kind={action.suggested.task}
                value={action.task}
                maxLength={500}
                onChange={(e) => updateAction(index, "task", e.target.value)}
              />
              <Field
                label="Owner"
                kind={action.suggested.owner}
                value={action.owner}
                maxLength={200}
                onChange={(e) => updateAction(index, "owner", e.target.value)}
              />
              <Field
                label="Due"
                kind={action.suggested.due && "AI"}
                type="date"
                value={action.due}
                onChange={(e) => updateAction(index, "due", e.target.value)}
              />
              <button
                type="button"
                aria-label={`Remove action item ${index + 1}`}
                className="mt-6 self-center text-stone-400 hover:text-red-700"
                onClick={() =>
                  setActions((rows) => rows.filter((_, i) => i !== index))
                }
              >
                <Trash2 size={16} />
              </button>
            </div>
          ))}
        </div>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="mt-3"
          onClick={() => setActions((rows) => [...rows, blankAction()])}
        >
          <Plus size={14} /> Add action item
        </Button>

        {error && (
          <p role="alert" className="mt-5 text-sm text-red-700">
            {error}
          </p>
        )}
        <div className="mt-7 flex items-center justify-end gap-3">
          {suggestion && (
            <span className="mr-auto text-xs text-stone-400">
              Suggested by {suggestion.model.replace("anthropic.", "")} ·{" "}
              {suggestion.prompt_version}
            </span>
          )}
          <Button
            variant="outline"
            type="button"
            onClick={onClose}
            disabled={saving}
          >
            Cancel
          </Button>
          <Button disabled={saving || parsing}>
            {saving ? "Saving…" : "Save agenda"}
          </Button>
        </div>
      </form>
    </dialog>
  );
}
