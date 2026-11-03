"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { compact } from "../_lib/format";
import { useNow, useStored } from "../_lib/api";
import { CommandPalette } from "./CommandPalette";
import { NAV, SYSTEM_NAV, navFor, useAdmin, type NavItem, type Theme } from "./context";
import { Icon, type IconName } from "./icons";
import { IconButton, Menu, MenuItem, MenuLabel, MenuSep, cx } from "./ui";

/**
 * The signed-in frame: the sidebar (the brand, every section with what is
 * waiting in it, collapsible to icons on a desktop and a drawer on a
 * phone), and the top bar (where you are, search, who is on the site right
 * now, freshness, theme, account).
 */
export function Shell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { overview } = useAdmin();
  const [collapsed, setCollapsed] = useStored<"0" | "1">("akarat-admin-nav", "0", ["0", "1"]);
  const [drawer, setDrawer] = useState(false);
  const [palette, setPalette] = useState(false);
  const current = navFor(pathname);
  const side = useRef<HTMLElement>(null);

  useEffect(() => setDrawer(false), [pathname]);

  useEffect(() => {
    document.title = `${current.label} · Admin · Akarat.ai`;
  }, [current.label]);

  // Ctrl/⌘ K or "/" opens search; Escape closes the phone menu.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement | null;
      const typing = !!el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName));
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPalette(p => !p);
      } else if (e.key === "/" && !typing && !e.metaKey && !e.ctrlKey) {
        e.preventDefault();
        setPalette(true);
      } else if (e.key === "Escape") {
        setDrawer(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (drawer) side.current?.querySelector<HTMLElement>("a, button")?.focus();
  }, [drawer]);

  const isCollapsed = collapsed === "1";
  return (
    <div className={cx("adm-shell", isCollapsed && "is-collapsed", drawer && "is-drawer-open")}>
      <a className="adm-skip" href="#adm-main">Skip to content</a>

      <aside ref={side} className="adm-side" aria-label="Admin sections">
        <div className="adm-side-head">
          <Link href="/admin" className="adm-brand" aria-label="Akarat.ai admin, overview">
            <img src="/assets/akarat-mark.png" alt="" width={26} height={33} />
            <span className="adm-brand-text">
              <b>Akarat.ai</b>
              <small>Admin</small>
            </span>
          </Link>
          <IconButton icon="x" label="Close menu" className="adm-side-close" onClick={() => setDrawer(false)} />
        </div>

        <nav className="adm-nav">
          {NAV.map(group => (
            <div key={group.title ?? "home"} className="adm-nav-group">
              {group.title && <div className="adm-nav-title">{group.title}</div>}
              <ul>
                {group.items.map(item => (
                  <NavLink key={item.href} item={item} active={current.href === item.href} count={item.count?.(overview)} />
                ))}
              </ul>
            </div>
          ))}
        </nav>

        <div className="adm-side-foot">
          <ul>
            <NavLink item={SYSTEM_NAV} active={current.href === SYSTEM_NAV.href} />
            <li>
              <a className="adm-nav-link" href="/" target="_blank" rel="noreferrer" title="View akarat.ai">
                <Icon name="external" size={18} />
                <span className="adm-nav-label">View akarat.ai</span>
              </a>
            </li>
          </ul>
          <button
            type="button"
            className="adm-collapse"
            onClick={() => setCollapsed(isCollapsed ? "0" : "1")}
            aria-pressed={isCollapsed}
            title={isCollapsed ? "Expand the sidebar" : "Collapse the sidebar"}
          >
            <Icon name="panel" size={17} />
            <span className="adm-nav-label">Collapse</span>
          </button>
        </div>
      </aside>
      <div className="adm-scrim" aria-hidden="true" onClick={() => setDrawer(false)} />

      <div className="adm-frame">
        <Topbar current={current} onMenu={() => setDrawer(true)} onSearch={() => setPalette(true)} />
        <main id="adm-main" className="adm-main" tabIndex={-1}>
          {children}
        </main>
      </div>

      {palette && <CommandPalette onClose={() => setPalette(false)} />}
    </div>
  );
}

function NavLink({ item, active, count }: { item: NavItem; active: boolean; count?: number }) {
  return (
    <li>
      <Link href={item.href} className="adm-nav-link" aria-current={active ? "page" : undefined} title={item.label}>
        <Icon name={item.icon} size={18} />
        <span className="adm-nav-label">{item.label}</span>
        {!!count && (
          <>
            <span className={cx("adm-nav-count", item.urgent && "is-urgent")} aria-hidden="true">{count > 99 ? "99+" : count}</span>
            <span className="adm-sr">, {count} waiting</span>
          </>
        )}
      </Link>
    </li>
  );
}

const THEMES: { value: Theme; label: string; icon: IconName }[] = [
  { value: "system", label: "Match the device", icon: "monitor" },
  { value: "light", label: "Light", icon: "sun" },
  { value: "dark", label: "Dark", icon: "moon" },
];

function Topbar({ current, onMenu, onSearch }: { current: NavItem; onMenu: () => void; onSearch: () => void }) {
  const { overview, overviewAt, overviewError, refreshOverview, theme, setTheme, signOut } = useAdmin();
  const [mac, setMac] = useState(false);
  const [spinning, setSpinning] = useState(false);
  const now = useNow(5000);
  useEffect(() => setMac(/Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent)), []);

  const age = overviewAt ? Math.max(0, Math.round((now - overviewAt) / 1000)) : null;
  const stale = overviewError && overviewError.status !== 501;
  const themeIcon = THEMES.find(t => t.value === theme)?.icon ?? "monitor";

  return (
    <header className="adm-top">
      <IconButton icon="menu" label="Open menu" className="adm-menu-btn" onClick={onMenu} />
      <div className="adm-crumbs" aria-label="You are here">
        <span className="adm-crumb-root">Admin</span>
        <Icon name="chevronRight" size={14} />
        <span className="adm-crumb-here">{current.label}</span>
      </div>

      <button type="button" className="adm-search-btn" onClick={onSearch} aria-label="Search or jump to a page">
        <Icon name="search" size={16} />
        <span>Search or jump to…</span>
        <kbd>{mac ? "⌘K" : "Ctrl K"}</kbd>
      </button>

      <div className="adm-top-right">
        {overview && (
          <Link href="/admin" className="adm-live" title="Browsers and app installs active in the last 2 minutes">
            <span className="adm-pulse" aria-hidden="true" />
            <b>{compact(overview.live.total)}</b>
            <span className="adm-live-word">online</span>
          </Link>
        )}
        <button
          type="button"
          className={cx("adm-fresh", stale && "is-stale")}
          onClick={async () => {
            setSpinning(true);
            await refreshOverview();
            setSpinning(false);
          }}
          title={stale ? `Couldn't refresh: ${overviewError?.message}` : "Figures refresh every 15 seconds. Refresh now"}
          aria-label="Refresh figures"
        >
          <Icon name="refresh" size={15} className={spinning ? "is-spinning" : undefined} />
          <span className="adm-fresh-text">{stale ? "Offline" : age === null ? "Loading" : age < 5 ? "Just now" : `${age < 60 ? `${age}s` : `${Math.floor(age / 60)}m`} ago`}</span>
        </button>

        <Menu label="Theme" trigger={<Icon name={themeIcon} size={18} />}>
          <MenuLabel>Appearance</MenuLabel>
          {THEMES.map(t => (
            <MenuItem key={t.value} checked={theme === t.value} onSelect={() => setTheme(t.value)}>
              {t.label}
            </MenuItem>
          ))}
        </Menu>

        <Menu label="Account" triggerClassName="adm-account-btn" trigger={<span className="adm-account-avatar" aria-hidden="true">A</span>}>
          <MenuLabel>Signed in as admin</MenuLabel>
          <MenuItem icon="sliders" href="/admin/system">System and session</MenuItem>
          <MenuItem icon="external" href="/" external>View akarat.ai</MenuItem>
          <MenuSep />
          <MenuItem icon="logout" danger onSelect={() => void signOut()}>Sign out</MenuItem>
        </Menu>
      </div>
    </header>
  );
}
