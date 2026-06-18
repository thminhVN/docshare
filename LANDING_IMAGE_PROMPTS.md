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

## How it works item image system prompt

Use this as the **system prompt** in ChatGPT before generating the three "How it
works" item images:

> You are generating a cohesive set of small SaaS landing-page illustrations for
> DocShare, a collaborative HTML document review app. Keep every image consistent
> with the current site theme: clean white or very pale zinc background, indigo
> primary accents (#4f46e5 / #6366f1), soft lavender support color (#eef2ff),
> neutral zinc text-like shapes, crisp flat-vector geometry, subtle soft shadows,
> rounded rectangles around 8-16px, generous whitespace, and a calm professional
> product feel. Do not include readable text, logos, watermarks, fake UI labels,
> or distorted lettering; use abstract bars and simple UI shapes instead. Avoid
> dark backgrounds, 3D rendering, photorealism, busy gradients, decorative orbs,
> cartoon mascots, and unrelated objects. The three outputs must feel like one
> matching icon/spot-illustration family.

Use these images if you decide to replace the current numbered circles in the
`How it works` section with visual assets. Suggested output size: **900 x 640**
for each image, transparent or white background.

### How it works 1 — Upload

> Small clean SaaS spot illustration for the "Upload" step. Show a simplified
> browser/document upload area with a centered HTML file card moving upward into
> a drop zone. The file card should suggest `.html` using abstract code brackets
> or simple code-line bars, not readable text. Add a small upward arrow icon and
> a few document content blocks. Use the DocShare style: white/pale zinc
> background, indigo accents, soft lavender highlights, neutral gray abstract
> text bars, crisp flat vector, subtle shadow, generous whitespace.

### How it works 2 — Share

> Small clean SaaS spot illustration for the "Share" step. Show a document card
> sending an invitation through email to two or three collaborator avatar circles.
> Include a simple envelope shape, link chip, and light connector lines, but no
> readable text. The composition should feel easy and collaborative, matching the
> same flat vector DocShare style: white/pale zinc background, indigo accents,
> soft lavender highlights, neutral gray UI bars, subtle shadow, crisp edges,
> generous whitespace.

### How it works 3 — Comment & iterate

> Small clean SaaS spot illustration for the "Comment & iterate" step. Show a
> document section with one highlighted block, a comment bubble anchored to that
> block, and a compact version/diff indicator suggesting iteration. Use tiny
> abstract lines for comments and document content, plus one small AI/export
> sparkle or wand-like icon if it stays subtle. Keep it consistent with DocShare:
> white/pale zinc background, indigo highlight, lavender accents, restrained
> green/red diff marks, flat vector, subtle shadow, no readable text, generous
> whitespace.

---

## After generating

1. Save each file to its path above (overwrite the placeholder).
2. If you use a different extension (e.g. `.png`), update the corresponding
   `src={~p"/images/landing/<name>.svg"}` in `home.html.heex`.
3. Reload the home page — no server restart needed.
