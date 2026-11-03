import { foldTail } from "./stats";

/** Answers by "model|effort", as stacked-bar segments: the three biggest, the rest as "Other". */
export function mixSegments(mix: { route: string; n: number }[]): { key: string; label: string; n: number; color: string }[] {
  const colors = ["var(--c1)", "var(--c2)", "var(--c3)"];
  return foldTail(mix, 3, n => ({ route: "Other", n })).map((m, i) => ({
    key: m.route,
    label: m.route.replace("|", " · "),
    n: m.n,
    color: m.route === "Other" ? "var(--c-muted)" : colors[i] ?? "var(--c-muted)",
  }));
}
