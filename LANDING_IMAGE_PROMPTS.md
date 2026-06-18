# Landing page image prompts

The landing page (`lib/docshare_web/controllers/page_html/home.html.heex`) currently
uses placeholder SVGs in `priv/static/images/landing/`. Generate real images with
ChatGPT (image generation), then **save each one over the matching path** (keep the
same filename, or use `.png`/`.webp` and update the `src` in `home.html.heex`).

**Shared style (prepend to every prompt for a cohesive set):**

> Modern, clean SaaS marketing illustration. Flat vector style with soft gradients.
> Primary color indigo/violet (#4f46e5, #6366f1) with light lavender (#eef2ff)
> accents on a white background. Friendly, professional, lots of whitespace, subtle
> soft shadows. No real text / no lorem ipsus (use abstract bars to suggest text so
> it doesn't render as garbled letters). High detail, crisp edges.

---

## 1. Hero — `priv/static/images/landing/hero.svg` (1200 × 900, portrait-ish)

> [shared style] A hero illustration of a team collaboratively reviewing an HTML
> document. Show a large document/page in the center with several distinct content
> blocks (a heading bar, paragraph lines, a small chart). Floating speech-bubble
> comment markers point to individual blocks, each with a tiny user avatar. One or
> two simplified people figures on the side adding comments. Convey real-time
> collaboration. Airy composition, indigo accents.

## 2. Showcase screenshot — `priv/static/images/landing/showcase.svg` (1600 × 900, wide)

> [shared style] A clean product UI mockup inside a rounded browser window. Left
> two-thirds: a rendered document with headings and paragraphs, one paragraph
> highlighted with an indigo outline and a small "2" comment count badge. Right
> third: a comment side panel showing two threaded comments with avatars and a
> text input at the bottom. Top bar has a version dropdown ("v2") and "Share" and
> "Compare" buttons. Use abstract bars instead of readable text. Realistic but
> minimal SaaS dashboard aesthetic.

## 3. Per-part commenting — `priv/static/images/landing/feature-comments.svg` (900 × 640)

> [shared style] Close-up illustration of a single document section (a heading plus
> a few paragraph lines) with one paragraph highlighted, and a comment thread
> bubble popping out from it containing two short comments with avatars. Emphasize
> the idea of anchoring a comment to one specific block. Indigo highlight.

## 4. Versions & rendered diff — `priv/static/images/landing/feature-versions.svg` (900 × 640)

> [shared style] Illustration of comparing two document versions: two stacked or
> side-by-side pages where some lines are highlighted green (added) and some red
> with a strikethrough (removed), like a rendered redline diff. Include a small
> vertical version timeline with dots labeled v1, v2, v3. Clean, git-diff feeling.

## 5. Share by email — `priv/static/images/landing/feature-share.svg` (900 × 640)

> [shared style] Illustration of sharing a document by email: an envelope opening
> with a small document and an invite link/chip coming out, surrounded by 3–4 user
> avatar circles connected by light lines (collaborators). Convey "invite people by
> email." Indigo accents, friendly.

---

## After generating

1. Save each file to its path above (overwrite the placeholder).
2. If you use a different extension (e.g. `.png`), update the corresponding
   `src={~p"/images/landing/<name>.svg"}` in `home.html.heex`.
3. Reload the home page — no server restart needed.
