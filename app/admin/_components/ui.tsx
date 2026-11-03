"use client";

import Link from "next/link";
import { createPortal } from "react-dom";
import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode,
} from "react";
import { Icon, type IconName } from "./icons";
import { compact, full, initials } from "../_lib/format";
import { labelOf, type Labelled, type Tone } from "../_lib/labels";
import type { Trend } from "../_lib/stats";
import type { Person } from "../_lib/types";

export const cx = (...c: (string | false | null | undefined)[]): string => c.filter(Boolean).join(" ");

/* ── Buttons ─────────────────────────────────────────────────────────── */

type Variant = "primary" | "secondary" | "ghost" | "danger" | "danger-ghost";

type ButtonProps = {
  children?: ReactNode;
  variant?: Variant;
  size?: "sm" | "md";
  icon?: IconName;
  iconEnd?: IconName;
  loading?: boolean;
  wide?: boolean;
} & Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children">;

export function Button({ children, variant = "secondary", size = "md", icon, iconEnd, loading, wide, className, disabled, type = "button", ...rest }: ButtonProps) {
  const s = size === "sm" ? 15 : 17;
  return (
    <button
      type={type}
      className={cx("adm-btn", `is-${variant}`, size === "sm" && "is-sm", wide && "is-wide", className)}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <span className="adm-spinner" aria-hidden="true" /> : icon && <Icon name={icon} size={s} />}
      {children !== undefined && <span>{children}</span>}
      {iconEnd && !loading && <Icon name={iconEnd} size={s} />}
    </button>
  );
}

export function ButtonLink({ href, external, children, variant = "secondary", size = "md", icon, iconEnd, className }: {
  href: string; external?: boolean; children: ReactNode; variant?: Variant; size?: "sm" | "md"; icon?: IconName; iconEnd?: IconName; className?: string;
}) {
  const s = size === "sm" ? 15 : 17;
  const cls = cx("adm-btn", `is-${variant}`, size === "sm" && "is-sm", className);
  const body = (
    <>
      {icon && <Icon name={icon} size={s} />}
      <span>{children}</span>
      {iconEnd && <Icon name={iconEnd} size={s} />}
    </>
  );
  return external ? (
    <a href={href} target="_blank" rel="noreferrer" className={cls}>{body}</a>
  ) : (
    <Link href={href} className={cls}>{body}</Link>
  );
}

export function IconButton({ icon, label, size = 18, className, ...rest }: {
  icon: IconName; label: string; size?: number; className?: string;
} & Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children" | "aria-label">) {
  return (
    <button type="button" className={cx("adm-icon-btn", className)} aria-label={label} title={label} {...rest}>
      <Icon name={icon} size={size} />
    </button>
  );
}

/* ── Badges ──────────────────────────────────────────────────────────── */

export function Badge({ tone = "neutral", children, dot, icon, title }: {
  tone?: Tone; children: ReactNode; dot?: boolean; icon?: IconName; title?: string;
}) {
  return (
    <span className={cx("adm-badge", `is-${tone}`)} title={title}>
      {dot && <i className="adm-badge-dot" aria-hidden="true" />}
      {icon && <Icon name={icon} size={12} />}
      {children}
    </span>
  );
}

/** A stored value with its words and tone, from one of the maps in labels.ts. */
export function StatusBadge({ map, value }: { map: Record<string, Labelled>; value: string }) {
  const l = labelOf(map, value);
  return <Badge tone={l.tone} dot>{l.label}</Badge>;
}

/* ── Layout ──────────────────────────────────────────────────────────── */

export function PageHeader({ title, subtitle, actions, eyebrow }: {
  title: ReactNode; subtitle?: ReactNode; actions?: ReactNode; eyebrow?: ReactNode;
}) {
  return (
    <div className="adm-page-head">
      <div className="adm-page-titles">
        {eyebrow && <div className="adm-eyebrow">{eyebrow}</div>}
        <h1 className="adm-h1">{title}</h1>
        {subtitle && <p className="adm-page-sub">{subtitle}</p>}
      </div>
      {actions && <div className="adm-page-actions">{actions}</div>}
    </div>
  );
}

export function Card({ title, caption, actions, children, className, flush, icon, style }: {
  title?: ReactNode; caption?: ReactNode; actions?: ReactNode; children?: ReactNode; className?: string;
  flush?: boolean; icon?: IconName; style?: CSSProperties;
}) {
  const id = useId();
  return (
    <section className={cx("adm-card", flush && "is-flush", className)} aria-labelledby={title ? id : undefined} style={style}>
      {(title || actions) && (
        <header className="adm-card-head">
          <div className="adm-card-titles">
            {title && (
              <h2 id={id} className="adm-card-title">
                {icon && <span className="adm-card-icon"><Icon name={icon} size={15} /></span>}
                {title}
              </h2>
            )}
            {caption && <p className="adm-card-caption">{caption}</p>}
          </div>
          {actions && <div className="adm-card-actions">{actions}</div>}
        </header>
      )}
      {children}
    </section>
  );
}

/** label · value · change against the previous period · a note · a trend line. */
export function StatTile({ label, value, icon, tone = "neutral", trend, trendNote, note, spark, href }: {
  label: string; value: string; icon?: IconName; tone?: Tone; trend?: Trend | null; trendNote?: string;
  note?: ReactNode; spark?: ReactNode; href?: string;
}) {
  const body = (
    <>
      <div className="adm-tile-head">
        <span className="adm-tile-label">{label}</span>
        {icon && <span className={cx("adm-tile-icon", `is-${tone}`)}><Icon name={icon} size={16} /></span>}
      </div>
      <div className="adm-tile-value">{value}</div>
      <div className="adm-tile-foot">
        {trend && (
          <span className={cx("adm-delta", trend.good === true && "is-good", trend.good === false && "is-bad")}>
            {trend.dir !== "flat" && <Icon name={trend.dir === "up" ? "arrowUp" : "arrowDown"} size={12} />}
            {trend.text}
          </span>
        )}
        {trend && trendNote && <span className="adm-tile-note">{trendNote}</span>}
        {!trend && note && <span className="adm-tile-note">{note}</span>}
      </div>
      {trend && note && <div className="adm-tile-note is-second">{note}</div>}
      {spark && <div className="adm-tile-spark">{spark}</div>}
    </>
  );
  return href ? (
    <Link href={href} className="adm-card adm-tile is-link">{body}</Link>
  ) : (
    <div className="adm-card adm-tile">{body}</div>
  );
}

/** A small "label / value" pair, for rows of secondary figures. */
export function Figure({ label, value, sub }: { label: string; value: ReactNode; sub?: ReactNode }) {
  return (
    <div className="adm-figure">
      <div className="adm-figure-label">{label}</div>
      <div className="adm-figure-value">{value}</div>
      {sub && <div className="adm-figure-sub">{sub}</div>}
    </div>
  );
}

export function KV({ items }: { items: { k: ReactNode; v: ReactNode }[] }) {
  return (
    <dl className="adm-kv">
      {items.map((it, i) => (
        <div key={i}>
          <dt>{it.k}</dt>
          <dd>{it.v}</dd>
        </div>
      ))}
    </dl>
  );
}

/* ── Controls ────────────────────────────────────────────────────────── */

export function Segmented<T extends string | number>({ value, options, onChange, label }: {
  value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; label: string;
}) {
  return (
    <div className="adm-seg" role="group" aria-label={label}>
      {options.map(o => (
        <button key={String(o.value)} type="button" className="adm-seg-btn" aria-pressed={o.value === value} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  );
}

/** One-of filters as a row of chips, each with its count when known. */
export function Chips<T extends string>({ value, options, onChange, label }: {
  value: T; options: { value: T; label: string; count?: number | null; urgent?: boolean }[]; onChange: (v: T) => void; label: string;
}) {
  return (
    <div className="adm-chips" role="group" aria-label={label}>
      {options.map(o => (
        <button
          key={o.value}
          type="button"
          className={cx("adm-chip", o.urgent && !!o.count && "is-urgent")}
          aria-pressed={o.value === value}
          onClick={() => onChange(o.value)}
        >
          <span>{o.label}</span>
          {o.count != null && <span className="adm-chip-count">{compact(o.count)}</span>}
        </button>
      ))}
    </div>
  );
}

export function SearchInput({ value, onChange, placeholder, label }: {
  value: string; onChange: (v: string) => void; placeholder: string; label: string;
}) {
  return (
    <div className="adm-search">
      <Icon name="search" size={16} />
      <input type="search" value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} aria-label={label} spellCheck={false} autoComplete="off" />
      {value && (
        <button type="button" className="adm-search-clear" onClick={() => onChange("")} aria-label="Clear search">
          <Icon name="x" size={14} />
        </button>
      )}
    </div>
  );
}

export function Select({ value, onChange, options, label, small, disabled }: {
  value: string; onChange: (v: string) => void; options: { value: string; label: string }[]; label: string; small?: boolean; disabled?: boolean;
}) {
  return (
    <div className={cx("adm-select", small && "is-sm")}>
      <select value={value} onChange={e => onChange(e.target.value)} aria-label={label} disabled={disabled}>
        {options.map(o => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
      <Icon name="chevronDown" size={14} />
    </div>
  );
}

/** An on/off setting that takes effect at once. */
export function Switch({ checked, onChange, label, hint, disabled }: {
  checked: boolean; onChange: (v: boolean) => void; label: string; hint?: ReactNode; disabled?: boolean;
}) {
  const id = useId();
  return (
    <div className="adm-switch-row">
      <div>
        <div id={id} className="adm-switch-label">{label}</div>
        {hint && <div className="adm-switch-hint">{hint}</div>}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-labelledby={id}
        className="adm-switch"
        disabled={disabled}
        onClick={() => onChange(!checked)}
      >
        <span />
      </button>
    </div>
  );
}

export function Toolbar({ children }: { children: ReactNode }) {
  return <div className="adm-toolbar">{children}</div>;
}

export function Pager({ page, pageSize, total, onPage }: { page: number; pageSize: number; total: number; onPage: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const from = total === 0 ? 0 : page * pageSize + 1;
  const to = Math.min(total, (page + 1) * pageSize);
  return (
    <div className="adm-pager">
      <span className="adm-pager-info">
        {total === 0 ? "No results" : <>Showing <b>{full(from)}–{full(to)}</b> of <b>{full(total)}</b></>}
      </span>
      <div className="adm-pager-btns">
        <IconButton icon="chevronLeft" label="Previous page" disabled={page <= 0} onClick={() => onPage(page - 1)} />
        <span className="adm-pager-page">Page {full(page + 1)} of {full(pages)}</span>
        <IconButton icon="chevronRight" label="Next page" disabled={page + 1 >= pages} onClick={() => onPage(page + 1)} />
      </div>
    </div>
  );
}

/* ── States ──────────────────────────────────────────────────────────── */

export function Empty({ icon = "layers", title, body, action, small }: {
  icon?: IconName; title: ReactNode; body?: ReactNode; action?: ReactNode; small?: boolean;
}) {
  return (
    <div className={cx("adm-empty", small && "is-small")}>
      <span className="adm-empty-icon"><Icon name={icon} size={small ? 18 : 22} /></span>
      <div className="adm-empty-title">{title}</div>
      {body && <div className="adm-empty-body">{body}</div>}
      {action && <div className="adm-empty-action">{action}</div>}
    </div>
  );
}

export function Callout({ tone = "info", title, children, icon, action }: {
  tone?: Tone; title?: ReactNode; children?: ReactNode; icon?: IconName; action?: ReactNode;
}) {
  const name = icon ?? (tone === "bad" ? "circleAlert" : tone === "warn" ? "alert" : tone === "good" ? "circleCheck" : "info");
  return (
    <div className={cx("adm-callout", `is-${tone}`)} role={tone === "bad" ? "alert" : undefined}>
      <Icon name={name} size={18} />
      <div className="adm-callout-body">
        {title && <div className="adm-callout-title">{title}</div>}
        {children && <div className="adm-callout-text">{children}</div>}
      </div>
      {action && <div className="adm-callout-action">{action}</div>}
    </div>
  );
}

/** A list or figure that could not load, with the server's reason and a retry. */
export function LoadError({ error, onRetry }: { error: { message: string; status?: number }; onRetry: () => void }) {
  const setup = error.status === 501;
  return (
    <Callout
      tone={setup ? "warn" : "bad"}
      title={setup ? "This needs a database update" : "Couldn't load this"}
      action={setup ? undefined : <Button size="sm" icon="refresh" onClick={onRetry}>Try again</Button>}
    >
      {error.message}
    </Callout>
  );
}

export const Skeleton = ({ w, h = 14, r }: { w?: number | string; h?: number; r?: number }) => (
  <span className="adm-skel" style={{ width: w, height: h, borderRadius: r }} aria-hidden="true" />
);

export function SkeletonRows({ rows = 6, cols = 5 }: { rows?: number; cols?: number }) {
  return (
    <div className="adm-skel-rows" aria-busy="true" aria-label="Loading">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="adm-skel-row">
          <Skeleton w={40} h={40} r={10} />
          {Array.from({ length: cols - 1 }, (_, j) => (
            <Skeleton key={j} w={`${j === 0 ? 34 : 14}%`} h={12} />
          ))}
        </div>
      ))}
    </div>
  );
}

/* ── People and pictures ─────────────────────────────────────────────── */

const AVATAR = ["green", "gold", "blue", "ink"] as const;
const hash = (s: string) => [...s].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7);

export function Avatar({ name, email, seed, size = 32 }: { name?: string | null; email?: string | null; seed: string; size?: number }) {
  return (
    <span
      className={cx("adm-avatar", `is-${AVATAR[hash(seed) % AVATAR.length]}`)}
      style={{ width: size, height: size, fontSize: Math.round(size * 0.38) }}
      aria-hidden="true"
    >
      {initials(name, email)}
    </span>
  );
}

/** Someone on the site: avatar, name, email and phone, as far as they are known. */
export function PersonBlock({ p, fallback }: { p: Person | null; fallback?: string | null }) {
  if (!p) return <span className="adm-cell-sub">{fallback || "—"}</span>;
  return (
    <div className="adm-person">
      <Avatar name={p.name ?? fallback} email={p.email} seed={p.id} size={30} />
      <div className="adm-person-text">
        <div className="adm-cell-strong">
          {p.name || fallback || "—"} {p.verified && <Badge tone="good" icon="shield">Verified</Badge>}
        </div>
        {p.email && <a href={`mailto:${p.email}`} className="adm-cell-sub adm-link-quiet" onClick={e => e.stopPropagation()}>{p.email}</a>}
        {p.phone && <div className="adm-cell-sub" dir="ltr">{p.phone}</div>}
      </div>
    </div>
  );
}

export function Thumb({ src, size = "md" }: { src: string | null | undefined; size?: "md" | "lg" }) {
  const [failed, setFailed] = useState(false);
  return src && !failed ? (
    // Supabase Storage URLs; next/image would need every bucket host configured.
    <img className={cx("adm-thumb", `is-${size}`)} src={src} alt="" loading="lazy" decoding="async" onError={() => setFailed(true)} />
  ) : (
    <span className={cx("adm-thumb", "is-empty", `is-${size}`)} aria-hidden="true">
      <Icon name="image" size={size === "lg" ? 28 : 16} />
    </span>
  );
}

/* ── Menus ───────────────────────────────────────────────────────────── */

type Spot = { top?: number; bottom?: number; left?: number; right?: number };

/**
 * A button that opens a list of actions. The list is fixed to the window
 * and rendered at the panel's root, so neither a table's scroll box nor its
 * sticky column can clip or cover it; it closes on scroll, Escape, Tab or a
 * click elsewhere, and arrow keys move through it.
 */
export function Menu({ label, trigger, children, align = "end", triggerClassName = "adm-icon-btn" }: {
  label: string; trigger: ReactNode; children: ReactNode; align?: "start" | "end"; triggerClassName?: string;
}) {
  const [spot, setSpot] = useState<Spot | null>(null);
  const [host, setHost] = useState<HTMLElement | null>(null);
  const btn = useRef<HTMLButtonElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const open = spot !== null;

  const close = useCallback((refocus = false) => {
    setSpot(null);
    if (refocus) btn.current?.focus();
  }, []);

  const toggle = () => {
    if (open || !btn.current) return close();
    const r = btn.current.getBoundingClientRect();
    const below = window.innerHeight - r.bottom;
    const s: Spot = below < 280 && r.top > below ? { bottom: window.innerHeight - r.top + 6 } : { top: r.bottom + 6 };
    if (align === "end") s.right = Math.max(8, window.innerWidth - r.right);
    else s.left = Math.max(8, r.left);
    setHost(btn.current.closest<HTMLElement>(".adm"));
    setSpot(s);
  };

  useEffect(() => {
    if (!open) return;
    list.current?.querySelector<HTMLElement>('[role^="menuitem"]:not(:disabled)')?.focus();
    const outside = (e: Event) => {
      const t = e.target as Node;
      if (!list.current?.contains(t) && !btn.current?.contains(t)) close();
    };
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        close(true);
      }
    };
    const away = () => close();
    document.addEventListener("pointerdown", outside, true);
    document.addEventListener("keydown", key, true);
    window.addEventListener("scroll", outside, true);
    window.addEventListener("resize", away);
    return () => {
      document.removeEventListener("pointerdown", outside, true);
      document.removeEventListener("keydown", key, true);
      window.removeEventListener("scroll", outside, true);
      window.removeEventListener("resize", away);
    };
  }, [open, close]);

  const onKeyDown = (e: ReactKeyboardEvent) => {
    const items = Array.from(list.current?.querySelectorAll<HTMLElement>('[role^="menuitem"]:not(:disabled)') ?? []);
    const i = items.indexOf(document.activeElement as HTMLElement);
    const go = (j: number) => {
      e.preventDefault();
      items[(j + items.length) % items.length]?.focus();
    };
    if (e.key === "ArrowDown") go(i + 1);
    else if (e.key === "ArrowUp") go(i - 1);
    else if (e.key === "Home") go(0);
    else if (e.key === "End") go(items.length - 1);
    else if (e.key === "Tab") close();
  };

  return (
    <>
      <button ref={btn} type="button" className={triggerClassName} aria-haspopup="menu" aria-expanded={open} aria-label={label} title={label} onClick={toggle}>
        {trigger}
      </button>
      {open &&
        host &&
        createPortal(
          <div
            ref={list}
            role="menu"
            aria-label={label}
            className="adm-menu"
            style={spot}
            onKeyDown={onKeyDown}
            onClick={e => {
              if ((e.target as HTMLElement).closest('[role^="menuitem"]')) close(true);
            }}
          >
            {children}
          </div>,
          host,
        )}
    </>
  );
}

export function MenuItem({ icon, children, onSelect, href, external, danger, disabled, checked }: {
  icon?: IconName; children: ReactNode; onSelect?: () => void; href?: string; external?: boolean;
  danger?: boolean; disabled?: boolean; checked?: boolean;
}) {
  const cls = cx("adm-menu-item", danger && "is-danger");
  const lead = icon ? <Icon name={icon} size={16} /> : checked !== undefined ? (
    <span className="adm-menu-check">{checked && <Icon name="check" size={15} />}</span>
  ) : null;
  if (href) {
    return external ? (
      <a role="menuitem" className={cls} href={href} target="_blank" rel="noreferrer">{lead}<span>{children}</span></a>
    ) : (
      <Link role="menuitem" className={cls} href={href}>{lead}<span>{children}</span></Link>
    );
  }
  return (
    <button
      type="button"
      role={checked !== undefined ? "menuitemradio" : "menuitem"}
      aria-checked={checked}
      className={cls}
      onClick={onSelect}
      disabled={disabled}
    >
      {lead}
      <span>{children}</span>
    </button>
  );
}

export const MenuSep = () => <div className="adm-menu-sep" role="separator" />;
export const MenuLabel = ({ children }: { children: ReactNode }) => <div className="adm-menu-label">{children}</div>;

/* ── Drawer ──────────────────────────────────────────────────────────── */

/**
 * A panel that slides in from the side, for one record's details and
 * actions. A native modal <dialog>: focus stays inside while it is open,
 * Escape closes it, and so does a click on the dimmed page behind.
 */
export function Drawer({ open, onClose, title, subtitle, children, footer }: {
  open: boolean; onClose: () => void; title: ReactNode; subtitle?: ReactNode; children: ReactNode; footer?: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const id = useId();
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    else if (!open && d.open) d.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      className="adm-drawer"
      aria-labelledby={id}
      onCancel={e => {
        e.preventDefault();
        onClose();
      }}
      onClick={e => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      {open && (
        <div className="adm-drawer-panel">
          <header className="adm-drawer-head">
            <div className="adm-drawer-titles">
              <h2 id={id}>{title}</h2>
              {subtitle && <div className="adm-drawer-sub">{subtitle}</div>}
            </div>
            <IconButton icon="x" label="Close" onClick={onClose} />
          </header>
          <div className="adm-drawer-body">{children}</div>
          {footer && <footer className="adm-drawer-foot">{footer}</footer>}
        </div>
      )}
    </dialog>
  );
}

export function Section({ title, children, aside }: { title: string; children: ReactNode; aside?: ReactNode }) {
  return (
    <div className="adm-section">
      <div className="adm-section-head">
        <h3>{title}</h3>
        {aside}
      </div>
      {children}
    </div>
  );
}

/** A scroll box for a wide table, reachable by keyboard so it can be scrolled without a mouse. */
export function TableScroll({ label, children, busy }: { label: string; children: ReactNode; busy?: boolean }) {
  return (
    <div className={cx("adm-table-scroll", busy && "is-busy")} role="region" aria-label={label} tabIndex={0} aria-busy={busy || undefined}>
      {children}
    </div>
  );
}
