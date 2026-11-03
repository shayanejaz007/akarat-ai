"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { ALL_NAV, useAdmin } from "./context";
import { Icon, type IconName } from "./icons";
import { cx } from "./ui";

type Command = { id: string; label: string; icon: IconName; group: string; keywords?: string; run: () => void };

/**
 * Ctrl/⌘ K: jump to any section, search listings, users, inquiries, bookings
 * or daily rentals for what was typed, or switch theme and sign out, from
 * the keyboard.
 */
export function CommandPalette({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const { refreshOverview, setTheme, signOut } = useAdmin();
  const ref = useRef<HTMLDialogElement>(null);
  const listId = useId();
  const [q, setQ] = useState("");
  const [active, setActive] = useState(0);

  useEffect(() => {
    ref.current?.showModal();
  }, []);

  const commands = useMemo<Command[]>(() => {
    const go = (href: string) => () => {
      onClose();
      router.push(href);
    };
    const term = q.trim();
    const t = term.toLowerCase();
    const enc = encodeURIComponent(term);
    const match = (c: Command) => !t || `${c.label} ${c.keywords ?? ""}`.toLowerCase().includes(t);
    const pages: Command[] = ALL_NAV.map(n => ({ id: `go${n.href}`, label: n.label, icon: n.icon, group: "Go to", keywords: n.keywords, run: go(n.href) }));
    const searches: Command[] = term
      ? [
          { id: "s-listings", label: `Search listings for “${term}”`, icon: "building", group: "Search", run: go(`/admin/listings?q=${enc}`) },
          { id: "s-users", label: `Search users for “${term}”`, icon: "users", group: "Search", run: go(`/admin/users?q=${enc}`) },
          { id: "s-inquiries", label: `Search inquiries for “${term}”`, icon: "inbox", group: "Search", run: go(`/admin/inquiries?q=${enc}`) },
          { id: "s-bookings", label: `Search bookings for “${term}”`, icon: "calendar", group: "Search", run: go(`/admin/bookings?q=${enc}`) },
          { id: "s-daily", label: `Search daily rentals for “${term}”`, icon: "bed", group: "Search", run: go(`/admin/daily-rentals?review=all&q=${enc}`) },
        ]
      : [];
    const actions: Command[] = [
      {
        id: "a-refresh",
        label: "Refresh the figures",
        icon: "refresh",
        group: "Actions",
        keywords: "reload update",
        run: () => {
          onClose();
          void refreshOverview();
        },
      },
      { id: "a-light", label: "Light theme", icon: "sun", group: "Actions", keywords: "appearance mode", run: () => { setTheme("light"); onClose(); } },
      { id: "a-dark", label: "Dark theme", icon: "moon", group: "Actions", keywords: "appearance mode night", run: () => { setTheme("dark"); onClose(); } },
      { id: "a-system", label: "Match the device's theme", icon: "monitor", group: "Actions", keywords: "appearance mode auto", run: () => { setTheme("system"); onClose(); } },
      {
        id: "a-site",
        label: "Open akarat.ai",
        icon: "external",
        group: "Actions",
        keywords: "website public",
        run: () => {
          onClose();
          window.open("/", "_blank", "noopener");
        },
      },
      {
        id: "a-out",
        label: "Sign out",
        icon: "logout",
        group: "Actions",
        keywords: "log out leave",
        run: () => {
          onClose();
          void signOut();
        },
      },
    ];
    return [...pages.filter(match), ...searches, ...actions.filter(match)];
  }, [q, onClose, router, refreshOverview, setTheme, signOut]);

  const at = Math.min(active, Math.max(0, commands.length - 1));
  const optionId = (i: number) => `${listId}-${i}`;

  useEffect(() => {
    document.getElementById(`${listId}-${at}`)?.scrollIntoView({ block: "nearest" });
  }, [at, listId]);

  const groups: { name: string; items: { c: Command; i: number }[] }[] = [];
  commands.forEach((c, i) => {
    const g = groups.find(x => x.name === c.group);
    if (g) g.items.push({ c, i });
    else groups.push({ name: c.group, items: [{ c, i }] });
  });

  return (
    <dialog
      ref={ref}
      className="adm-palette"
      aria-label="Search and commands"
      onCancel={e => {
        e.preventDefault();
        onClose();
      }}
      onClick={e => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="adm-palette-panel">
        <div className="adm-palette-input">
          <Icon name="search" size={18} />
          <input
            value={q}
            onChange={e => {
              setQ(e.target.value);
              setActive(0);
            }}
            onKeyDown={e => {
              if (e.key === "ArrowDown") {
                e.preventDefault();
                setActive(Math.min(commands.length - 1, at + 1));
              } else if (e.key === "ArrowUp") {
                e.preventDefault();
                setActive(Math.max(0, at - 1));
              } else if (e.key === "Enter") {
                e.preventDefault();
                commands[at]?.run();
              }
            }}
            placeholder="Search listings, people, inquiries… or jump to a page"
            role="combobox"
            aria-expanded="true"
            aria-controls={listId}
            aria-activedescendant={commands.length ? optionId(at) : undefined}
            aria-autocomplete="list"
            spellCheck={false}
            autoComplete="off"
          />
          <kbd>Esc</kbd>
        </div>
        <div id={listId} role="listbox" aria-label="Results" className="adm-palette-list">
          {commands.length === 0 && <div className="adm-palette-empty">Nothing matches “{q.trim()}”.</div>}
          {groups.map(g => (
            <div key={g.name} role="group" aria-label={g.name}>
              <div className="adm-palette-group" aria-hidden="true">{g.name}</div>
              {g.items.map(({ c, i }) => (
                <div
                  key={c.id}
                  id={optionId(i)}
                  role="option"
                  aria-selected={i === at}
                  className={cx("adm-palette-item", i === at && "is-active")}
                  onMouseMove={() => i !== at && setActive(i)}
                  onClick={() => c.run()}
                >
                  <Icon name={c.icon} size={17} />
                  <span>{c.label}</span>
                  {i === at && <Icon name="arrowRight" size={15} className="adm-palette-enter" />}
                </div>
              ))}
            </div>
          ))}
        </div>
        <div className="adm-palette-foot">
          <span><kbd>↑</kbd><kbd>↓</kbd> move</span>
          <span><kbd>Enter</kbd> open</span>
          <span><kbd>Esc</kbd> close</span>
        </div>
      </div>
    </dialog>
  );
}
