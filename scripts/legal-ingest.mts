/**
 * Loads prepared Jordanian legal sources into the Akarat legal library
 * (legal_sources / legal_passages, 0021_legal_ai.sql).
 *
 *   node scripts/legal-ingest.mts [folder] [--apply] [--embed]
 *
 *   folder    default data/legal. Every .md file in it is one source, except
 *             README.md and files whose names start with "_".
 *   (none)    a dry run: reads and checks every file, writes nothing.
 *   --apply   writes them with the service-role key: each source by its slug
 *             (updated if it is already there), its passages replaced.
 *   --embed   also embeds passages that have no embedding yet, with Voyage
 *             (VOYAGE_API_KEY), so the library can be searched by meaning.
 *
 * Needs NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY for --apply.
 * The file format and the review it records are in data/legal/README.md.
 *
 * This reads files the team prepared from official or licensed sources. It
 * fetches nothing from anywhere: what goes into the library is exactly what
 * a person checked.
 */
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";
import { parseSourceFile, type Parsed } from "../lib/legal/ingest.ts";
import { embed } from "../lib/legal/library.ts";

const args = process.argv.slice(2);
const dir = args.find(a => !a.startsWith("--")) ?? "data/legal";
const apply = args.includes("--apply");
const wantEmbed = args.includes("--embed");

const files = readdirSync(dir)
  .filter(f => f.endsWith(".md") && !f.startsWith("_") && f.toLowerCase() !== "readme.md")
  .sort();
if (!files.length) {
  console.log(`No source files in ${dir}. See ${join(dir, "README.md")} for the format.`);
  process.exit(0);
}

const parsed: { file: string; p: Parsed }[] = [];
let failed = 0;
const slugs = new Map<string, string>();
for (const file of files) {
  const r = parseSourceFile(readFileSync(join(dir, file), "utf8"));
  if ("errors" in r) {
    failed++;
    console.log(`✗ ${file}`);
    for (const e of r.errors) console.log(`    ${e}`);
    continue;
  }
  if (slugs.has(r.source.slug)) {
    failed++;
    console.log(`✗ ${file}\n    slug ${r.source.slug} is also used by ${slugs.get(r.source.slug)}`);
    continue;
  }
  slugs.set(r.source.slug, file);
  const articles = r.passages.filter(x => x.article_no != null).length;
  console.log(`✓ ${file}  ${r.source.slug}  ${r.source.kind}  ${r.source.verification}  ${r.passages.length} passages${articles ? `, ${articles} with article numbers` : ""}`);
  for (const w of r.warnings) console.log(`    note: ${w}`);
  parsed.push({ file, p: r });
}
if (failed) {
  console.log(`\n${failed} file(s) need fixing; nothing was written.`);
  process.exit(1);
}
if (!apply) {
  console.log(`\nDry run: ${parsed.length} source(s) read. Run again with --apply to write them.`);
  process.exit(0);
}

const URL_ = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !SERVICE) {
  console.log("Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to write to the library.");
  process.exit(1);
}
const sb = createClient(URL_, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });

for (const { file, p } of parsed) {
  const { data: src, error } = await sb
    .from("legal_sources")
    .upsert({ ...p.source, updated_at: new Date().toISOString() }, { onConflict: "slug" })
    .select("id")
    .single();
  if (error || !src) {
    console.log(`✗ ${file}: ${error?.message ?? "not saved"}`);
    process.exit(1);
  }
  const del = await sb.from("legal_passages").delete().eq("source_id", src.id);
  if (del.error) {
    console.log(`✗ ${file}: ${del.error.message}`);
    process.exit(1);
  }
  for (let i = 0; i < p.passages.length; i += 200) {
    const ins = await sb.from("legal_passages").insert(p.passages.slice(i, i + 200).map(x => ({ ...x, source_id: src.id })));
    if (ins.error) {
      console.log(`✗ ${file}: ${ins.error.message}`);
      process.exit(1);
    }
  }
  console.log(`→ ${p.source.slug}: ${p.passages.length} passages written`);
}

if (wantEmbed) {
  if (!process.env.VOYAGE_API_KEY) {
    console.log("--embed needs VOYAGE_API_KEY; the library still works by full text and exact citation without it.");
    process.exit(1);
  }
  let done = 0;
  for (;;) {
    const { data, error } = await sb
      .from("legal_passages")
      .select("id, article, body, legal_sources(title_ar)")
      .is("embedding", null)
      .limit(64);
    if (error) {
      console.log(`✗ reading passages: ${error.message}`);
      process.exit(1);
    }
    if (!data?.length) break;
    const texts = data.map(r => {
      const title = (r as unknown as { legal_sources: { title_ar: string } | null }).legal_sources?.title_ar ?? "";
      return `${title} ${r.article ?? ""}\n${r.body}`.slice(0, 16000);
    });
    const vectors = await embed(texts, "document");
    if (!vectors) {
      console.log("✗ Voyage did not return embeddings; stopping. Nothing half-written: passages without one are simply not searched by meaning.");
      process.exit(1);
    }
    for (const [i, r] of data.entries()) {
      const up = await sb.from("legal_passages").update({ embedding: `[${vectors[i].join(",")}]` }).eq("id", r.id);
      if (up.error) {
        console.log(`✗ passage ${r.id}: ${up.error.message}`);
        process.exit(1);
      }
    }
    done += data.length;
    console.log(`  embedded ${done}`);
  }
  console.log(`→ ${done} passage(s) embedded`);
}
console.log("\nDone. Only sources marked verified are searched by Ask a Lawyer.");
