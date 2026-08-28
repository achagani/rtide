# RTIDE design playbook

Use this playbook for substantive tweb artifacts. The goal is not decoration; it
is an authored visual explanation whose form reflects its subject.

## 1. Establish a visual thesis

Write one private sentence before coding: “This should feel like ___ because ___.”
Choose a direction that carries meaning, such as:

- cartographic field guide — place, travel, geography, logistics
- editorial dossier — research, synthesis, people, competing evidence
- data observatory — metrics, trends, rankings, uncertainty
- technical blueprint — architecture, code, systems, dependencies
- chronological atlas — history, roadmaps, incident sequences
- comparative atelier — products, options, tradeoffs, recommendations
- visual essay — culture, ideas, narrative, image-led explanation

Do not expose these labels mechanically in the page. Use them to make design
decisions. Change direction between outputs when the subject changes.

## 2. Build information architecture

Lead with the answer or central idea, then reveal evidence and detail. Prefer a
small number of distinct chapters over many equal cards. Give every section a job.
Use progressive disclosure for supporting detail, and keep navigation or a compact
contents rail available on long pages.

## 3. Create a content-specific anchor

Include at least one high-value visual when the material supports it:

- a real map or route with labels, scale, coordinates, and destination links
- an SVG diagram whose geometry explains relationships
- a chart with units, baseline, legend, and source
- an annotated image or comparison plate
- a timeline with meaningful intervals rather than evenly spaced decoration
- a typographic fact, quote, or recommendation composed as the page’s focal point

Prefer inline SVG and CSS for diagrams and charts. Use sourced images where they
add evidence or orientation; provide alt text, captions, and nearby source links.

## 4. Compose, do not stack

Avoid “card soup.” Use grids only when items are genuinely peers. Vary density and
width: a full-bleed visual can transition into a narrow reading column, a side note,
then a structured comparison. Allow whitespace to establish hierarchy. Asymmetry,
overlap, borders, texture, and restrained motion are welcome when they clarify the
visual thesis and remain legible.

Avoid default AI aesthetics: purple-blue gradients, glass panels everywhere,
excessive pills, identical rounded cards, giant hero copy, and decorative metrics.

## 5. Art-direct the system

- Typography: choose a display/body/mono hierarchy using robust system fallbacks.
- Color: derive a restrained palette from the subject; maintain accessible contrast.
- Shape: choose a coherent geometry—editorial rules, map contours, technical nodes,
  soft organic fields, or another subject-led language.
- Detail: design captions, legends, source notes, focus states, and empty states.
- Motion: use subtle transitions only where they communicate change or navigation;
  respect `prefers-reduced-motion`.

## 6. Verify at the output surface

Render to the registered workspace tweb pane, then inspect at its actual dimensions.
Check the first viewport, hierarchy, overflow, image loading, links, contrast, and
small-width behavior. The first screen should deliver value without a wasteful hero.
Revise once if it still resembles an unmodified template.
