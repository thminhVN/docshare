# DocShare favicon and logo prompts

Use these prompts in ChatGPT image generation or another design tool to create a
consistent favicon and logo set for DocShare.

## System prompt

> You are designing brand assets for DocShare, a clean SaaS web app for
> collaborative HTML document review. Match the current website theme: white and
> very pale zinc backgrounds, indigo primary color (#4f46e5 / #6366f1), soft
> lavender accents (#eef2ff), neutral zinc text colors, crisp flat geometry, and
> a calm professional product feel. Avoid orange, mascots, complex illustrations,
> photorealism, gradients that dominate the mark, tiny unreadable details, and
> generic file icons. The mark must work at favicon size and as a header logo.

## Favicon prompt

> Create a simple square favicon for DocShare. Concept: a document page with a
> small anchored comment marker or speech bubble, suggesting review comments on
> HTML sections. Use a white or transparent background, indigo primary stroke or
> fill, one lavender accent, and crisp flat-vector edges. Keep the silhouette
> recognizable at 16x16 and 32x32. No text, no letters, no shadows heavier than a
> subtle hint. Export as 1024x1024 PNG and SVG.

## Logo mark prompt

> Create a clean logo mark for DocShare. Concept: an HTML document block and a
> comment bubble connected to a specific line, with a subtle version/check cue.
> Use indigo (#4f46e5 / #6366f1), lavender (#eef2ff), and zinc gray only. Flat
> vector, minimal geometry, rounded corners around 8-16px, strong silhouette,
> balanced whitespace. No readable text inside the icon. Export as SVG with
> transparent background.

## Horizontal logo prompt

> Create a horizontal logo for DocShare: the logo mark on the left and the word
> "DocShare" on the right. Use a modern geometric sans-serif wordmark, dark zinc
> text, indigo accent in the mark, and a compact SaaS header proportion. The logo
> should look clear on a white navigation bar and remain readable at 160px wide.
> Export as SVG with transparent background.

## Recommended files

Save final assets as:

1. `priv/static/images/brand/favicon.svg`
2. `priv/static/images/brand/favicon-1024.png`
3. `priv/static/images/brand/logo-horizontal.svg`
4. `priv/static/images/brand/logo-horizontal-1800.png`
5. `priv/static/images/brand/logo-mark.svg`
6. `priv/static/images/brand/logo-mark-1024.png`

Also regenerate `priv/static/favicon.ico` from the favicon SVG or PNG for
clients that request the legacy root favicon path directly.
