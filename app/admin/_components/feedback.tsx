"use client";

import { createContext, useCallback, useContext, useEffect, useId, useMemo, useRef, useState, type ReactNode } from "react";
import { Icon } from "./icons";
import { Button, IconButton, cx } from "./ui";

/*
 * Toasts, and the two questions the panel asks before acting (are you sure,
 * and why). They replace window.alert / confirm / prompt, which cannot be
 * styled, block the page, and tell nobody what happened afterwards.
 */

export type ToastInput = { tone?: "good" | "bad" | "info"; title: string; body?: string; action?: { label: string; run: () => void } };
type Toast = ToastInput & { id: number };

export type ConfirmOptions = { title: string; body?: ReactNode; confirm?: string; cancel?: string; danger?: boolean };
export type AskOptions = ConfirmOptions & { label: string; placeholder?: string; required?: boolean; initial?: string; maxLength?: number };

type Request =
  | { kind: "confirm"; opts: ConfirmOptions; resolve: (ok: boolean) => void }
  | { kind: "ask"; opts: AskOptions; resolve: (text: string | null) => void };

type Feedback = {
  toast: (t: ToastInput) => void;
  confirm: (o: ConfirmOptions) => Promise<boolean>;
  ask: (o: AskOptions) => Promise<string | null>;
};

const Ctx = createContext<Feedback | null>(null);

export function useFeedback(): Feedback {
  const v = useContext(Ctx);
  if (!v) throw new Error("useFeedback outside FeedbackProvider");
  return v;
}

export function FeedbackProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [request, setRequest] = useState<Request | null>(null);
  const seq = useRef(0);

  const dismiss = useCallback((id: number) => setToasts(ts => ts.filter(t => t.id !== id)), []);

  const toast = useCallback(
    (t: ToastInput) => {
      const id = ++seq.current;
      setToasts(ts => [...ts.slice(-3), { ...t, id }]);
      setTimeout(() => dismiss(id), t.tone === "bad" || t.action ? 8000 : 4500);
    },
    [dismiss],
  );

  const confirm = useCallback((opts: ConfirmOptions) => new Promise<boolean>(resolve => setRequest({ kind: "confirm", opts, resolve })), []);
  const ask = useCallback((opts: AskOptions) => new Promise<string | null>(resolve => setRequest({ kind: "ask", opts, resolve })), []);

  const value = useMemo(() => ({ toast, confirm, ask }), [toast, confirm, ask]);

  return (
    <Ctx.Provider value={value}>
      {children}
      <div className="adm-toasts" aria-live="polite" aria-relevant="additions">
        {toasts.map(t => (
          <div key={t.id} className={cx("adm-toast", `is-${t.tone ?? "info"}`)} role={t.tone === "bad" ? "alert" : "status"}>
            <Icon name={t.tone === "good" ? "circleCheck" : t.tone === "bad" ? "circleAlert" : "info"} size={18} />
            <div className="adm-toast-text">
              <div className="adm-toast-title">{t.title}</div>
              {t.body && <div className="adm-toast-body">{t.body}</div>}
            </div>
            {t.action && (
              <button
                type="button"
                className="adm-toast-action"
                onClick={() => {
                  t.action?.run();
                  dismiss(t.id);
                }}
              >
                {t.action.label}
              </button>
            )}
            <IconButton icon="x" label="Dismiss" size={15} className="adm-toast-close" onClick={() => dismiss(t.id)} />
          </div>
        ))}
      </div>
      {request && <Question key={seq.current} request={request} onDone={() => setRequest(null)} />}
    </Ctx.Provider>
  );
}

function Question({ request, onDone }: { request: Request; onDone: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const id = useId();
  const o = request.opts;
  const [text, setText] = useState(request.kind === "ask" ? request.opts.initial ?? "" : "");
  const [tried, setTried] = useState(false);
  const max = request.kind === "ask" ? request.opts.maxLength ?? 500 : 0;
  const missing = request.kind === "ask" && !!request.opts.required && !text.trim();

  useEffect(() => {
    ref.current?.showModal();
  }, []);

  const finish = (ok: boolean) => {
    if (request.kind === "confirm") request.resolve(ok);
    else request.resolve(ok ? text.trim() : null);
    ref.current?.close();
    onDone();
  };

  return (
    <dialog
      ref={ref}
      className="adm-dialog"
      aria-labelledby={id}
      onCancel={e => {
        e.preventDefault();
        finish(false);
      }}
    >
      <form
        onSubmit={e => {
          e.preventDefault();
          if (missing) return setTried(true);
          finish(true);
        }}
      >
        <div className="adm-dialog-body">
          <div className="adm-dialog-head">
            <span className={cx("adm-dialog-icon", o.danger && "is-danger")}>
              <Icon name={o.danger ? "alert" : request.kind === "ask" ? "message" : "info"} size={20} />
            </span>
            <h2 id={id}>{o.title}</h2>
          </div>
          {o.body && <div className="adm-dialog-text">{o.body}</div>}
          {request.kind === "ask" && (
            <label className="adm-field">
              <span className="adm-field-label">
                {request.opts.label}
                {!request.opts.required && <small> (optional)</small>}
              </span>
              <textarea
                value={text}
                onChange={e => setText(e.target.value)}
                rows={4}
                maxLength={max}
                placeholder={request.opts.placeholder}
                aria-invalid={(tried && missing) || undefined}
                dir="auto"
              />
              <span className={cx("adm-field-hint", tried && missing && "is-bad")}>
                {tried && missing ? "Write a reason first: the owner sees it." : `${text.length} / ${max}`}
              </span>
            </label>
          )}
        </div>
        <div className="adm-dialog-foot">
          <Button variant="ghost" onClick={() => finish(false)}>{o.cancel ?? "Cancel"}</Button>
          <Button type="submit" variant={o.danger ? "danger" : "primary"}>{o.confirm ?? "Confirm"}</Button>
        </div>
      </form>
    </dialog>
  );
}

/** Copies a value (an id, an email) and says so. */
export function CopyButton({ text, label = "Copy" }: { text: string; label?: string }) {
  const { toast } = useFeedback();
  return (
    <IconButton
      icon="copy"
      label={label}
      size={15}
      className="is-sm"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(text);
          toast({ tone: "good", title: "Copied" });
        } catch {
          toast({ tone: "bad", title: "Couldn't copy", body: "The browser blocked the clipboard." });
        }
      }}
    />
  );
}
