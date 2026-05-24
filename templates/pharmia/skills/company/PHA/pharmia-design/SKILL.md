---
name: "pharmia-design"
description: "Apply Pharmia's brand design system to any UI work. Use when building or styling components, pages, cards, or external tools for Pharmia. Provides tokens, patterns, rules, and common pitfalls extracted from the Figma source of truth and real codebase patterns."
slug: "pharmia-design"
metadata:
  paperclip:
    slug: "pharmia-design"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-design"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-design"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-design"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-design"
---


# Pharmia Design System

Authoritative design tokens and patterns for Pharmia, extracted from the Figma file (`3wO37CgmyZLjhrTdFrMyOr`) and cross-referenced with the actual codebase (`apps/web/src/`). Codebase is the implementation reference; Figma is the original design intent.

## When to Use

- Building or modifying Pharmia frontend components
- Styling third-party tools to match the Pharmia brand (Swiish, LinkStack, landing pages)
- Creating marketing materials, business cards, social media templates
- Reviewing UI for brand consistency

## Design Philosophy

**Sage glow is the signature.** Every surface, every interaction whispers green. Shadows are green-tinted. Glows are sage. Focus rings are sage. The brand lives in the light — not neon, not dark-mode-first. Pharmia is a pharmacy garden: clinical precision wrapped in natural warmth.

**Surfaces are barely-there gradients.** White-to-mint, mint-to-white, never bold color transitions. The Figma uses `#FFFFFF -> #F9FDF7` or `#F6FCF3 -> #FCFEFB` — differences so subtle you feel them more than see them.

**Light is the default.** The platform is light-mode-first. Dark elements (`#1D241C`) are used for emphasis (OPEN consultation cards, login CTA, footer, banner) — not as the base surface.

**Reuse before reinvention.** The codebase has 40+ shadcn/ui components. Compose and adapt them. Building new primitives creates drift and maintenance burden.

## Design Identity

- **Personality:** Organic clinical professionalism. Nature-infused healthcare.
- **Feel:** Calm, trustworthy, grounded.
- **Audience:** Quebec pharmacists, pharmacy owners, healthcare professionals. French-first.
- **Primary font:** Afacad (Google Fonts) — the app font. No exceptions in-app.
- **Marketing headline font:** Montserrat 600 (72px, -5% letter-spacing) — service website hero headings only.
- **Presentation font:** PP Fragment — slide decks only, never in app or website.

---

## Common Pitfalls

These are real problems that have occurred repeatedly. Read them BEFORE writing any UI code.

### 1. Not reusing existing components

**The #1 mistake.** Creating new primitive elements instead of adapting existing shadcn/ui components. The codebase has `Button`, `Card`, `Badge`, `Tabs`, `Dialog`, `ScrollArea`, etc. — use them.

- Never create a raw `<button>` with custom styles when `<Button variant="...">` exists
- Never create a raw card `<div>` when `<Card>` exists
- If a component pattern exists (tabs, pills, drawers), adapt it — don't reinvent
- Goal: **near-zero new primitive components**, only compose and adapt existing ones
- Check `apps/web/src/components/ui/` before building anything

### 2. Hardcoded hex values instead of CSS variables

The app has a CSS variable system in `index.css` mapped through Tailwind `@theme inline`. Use Tailwind semantic classes, not hardcoded hex.

**Wrong:** `text-[#1d241c]`, `bg-[#bbd8a3]`, `border-[#6f826a]`
**Right:** `text-foreground`, `bg-primary`, `text-muted-foreground`

Key mappings (see full list in `apps/web/src/index.css`):
- `--background` (`#F6FCF3`) -> `bg-background`
- `--foreground` (`#1D241C`) -> `text-foreground`
- `--primary` (`#BBD8A3`) -> `bg-primary`, `text-primary`
- `--muted-foreground` (`#6F826A`) -> `text-muted-foreground`
- `--border` (`#BBD8A3`) -> `border-border`
- `--brand` (`#BF9264`) -> `text-brand`
- `--destructive` -> `bg-destructive`

Only use hardcoded hex for colors NOT in the token system (status colors, one-off effects).

### 3. Redundant font-[Afacad]

The theme sets ALL font families to Afacad (`--font-sans`, `--font-mono`, `--font-serif`). Adding `font-[Afacad]` to every element is noise. Only use it when building OUTSIDE the app (external tools, standalone HTML, Swiish cards).

### 4. Breaking existing functionality

- Never add features that break the surrounding page (full reloads, navigation side-effects)
- Never modify components you weren't asked to touch — "look at the other window, that we modified but shouldnt have"
- Don't introduce regressions: check that interactive elements keep their behavior
- SPA rule: **never use `window.location.reload()`** — use React router navigation

### 5. Mobile responsiveness

Every UI change must work at 430px viewport (the most common mobile feedback width). Common failures:
- Buttons that look fine on desktop but are "atrocious" on mobile
- Layout that doesn't adapt — don't just shrink, redesign for the context
- Missing `cursor-pointer` on interactive elements
- Overflow/scroll issues at small widths
- Use `useIsMobile()` hook when desktop/mobile need different layouts

### 6. Wrong defaults and unnecessary additions

- Don't add elements that weren't asked for — "remove the echo button on the top right actually its fine"
- Don't apply random colors — "we dont need it to be red"
- Don't add filler text — "remove 'intelligent'"
- Every element must be intentional and adapted to context, no weird defaults
- Don't overfit fixes: find the general pattern, not the specific symptom

### 7. Accessibility basics

- `DialogContent` requires a `DialogTitle` (even if visually hidden with `VisuallyHidden`)
- Interactive elements need `cursor-pointer`
- Form inputs need labels
- Use semantic HTML (`button` for actions, `a` for navigation)

### 8. i18n violations

All UI strings must go through `useTranslation()` / `t()`. Never hardcode French text in JSX. The fallback string (second arg to `t()`) is fine for initial copy.

### 9. External tools not matching brand

When styling external tools (Swiish, LinkStack, etc.), the Pharmia brand must apply:
- Afacad font via Google Fonts import
- Pharmia green palette, not default tool colors
- Same border radius, shadow, and spacing conventions
- Test that the branded version actually renders (don't assume)

### 10. Contrast failures on hover/state changes

**Always verify text remains readable against its background in ALL states** (default, hover, active, focus, disabled). Common failure: a tool or framework sets `--button-text-hover-color: #FFFFFF` in `:root` — white text becomes invisible on Pharmia's light sage/white surfaces.

- Before applying custom CSS to third-party tools, audit their CSS variable chain for hover/focus/active color overrides that assume dark backgrounds
- Pharmia backgrounds are light (`#F6FCF3`, `#FFFFFF`, `#F9FDF7`) — white text is NEVER readable on them
- Valid hover text colors on light surfaces: `#1D241C` (foreground), `#2C7326` (action deep), `#6F826A` (muted)
- Valid hover text on dark surfaces (`#1D241C`, `#232B21`): `#F6FCF3`, `#FFFFFF`, `#BBD8A3`
- When overriding third-party CSS, check ALL state variables (not just the base color) — hover, active, visited states often come from different vars

---

## CSS Variable System

The single source of truth for colors in the app is `apps/web/src/index.css`. Variables are defined in `:root` and mapped through Tailwind's `@theme inline` block.

**Note:** Dark mode (`.dark`) currently has IDENTICAL values to light mode — it is not yet implemented. The dark mode tokens below are from Figma design intent, not shipped code.

### Core Tokens

- `--background`: `#F6FCF3` — Page background
- `--foreground`: `#1D241C` — Primary text
- `--card`: `#FFFFFF` — Card surfaces
- `--card-foreground`: `#1D241C` — Card text
- `--primary`: `#BBD8A3` — Brand sage, focus rings, borders
- `--primary-foreground`: `#1D241C` — Text on primary
- `--muted`: `#BBD8A3` — Muted surfaces
- `--muted-foreground`: `#6F826A` — Secondary text
- `--accent`: `#BBD8A3` — Accent highlights
- `--destructive`: `#FF3333` — Error/danger actions
- `--border`: `#BBD8A3` — Default borders
- `--input`: `#BBD8A3` — Input borders
- `--ring`: `#FFFFFF` — Focus ring (white in current impl)
- `--brand`: `#BF9264` — Gold accent (product names, premium)
- `--brand-secondary`: `#FFDAB5` — Light gold

### Status Colors (CSS custom properties)

- Completed: `--status-completed-bg: #72EACC` / `--status-completed-text: #4C872D`
- Open: `--status-open-bg: #C4C4C4` / `--status-open-text: #454545`
- Recommendations Ready: `--status-recommendations-ready-bg: #7BBFFF` / `--status-recommendations-ready-text: #2062A0`
- In Progress: `--status-conversation-in-progress-bg: #FFEEAC` / `--status-conversation-in-progress-text: #614600`
- Cancelled: `--status-cancelled-bg: #FF846E` / `--status-cancelled-text: #6A190B`

### Shadows (green-tinted via HSL)

The shadow scale uses `hsl(120 15% 25% / opacity)` — a forest-green tint. Never use pure gray shadows.

```css
--shadow-2xs: 0 1px 3px 0px hsl(120 15% 25% / 0.08);
--shadow-sm: 0 1px 3px 0px hsl(120 15% 25% / 0.12), 0 1px 2px -1px hsl(120 15% 25% / 0.12);
--shadow-lg: 0 1px 3px 0px hsl(120 15% 25% / 0.12), 0 4px 6px -1px hsl(120 15% 25% / 0.12);
```

---

## Color Palette (Full Reference)

### Sage Scale (light tints, most to least saturated)

`#BBD8A3` > `#D7E8C9` > `#DFF4D9` > `#E4F0DD` > `#E7F7DE` > `#EAF3E3` > `#EEFFE0` > `#F0FAEB` > `#F7FBF7` > `#F9FDF7` > `#FCFEFB` > `#F6FCF3`

### Dark Scale

`#1D241C` > `#232B21` > `#2C3529` > `#3A4838` > `#4C5F4A` > `#545A52` > `#6F826A`

### Action Colors

- Action: `#53A329` — Primary buttons, CTAs
- Action hover: `#317128` (light) / `#6FBF4A` (dark)
- Action deep: `#2C7326` — Links, strong emphasis
- Softer green: `#419735` — Alternate CTA shade

### Accent Colors

- Sage: `#BBD8A3` — Brand primary, glows, highlights, borders
- Gold: `#BF9264` — Brand secondary, product names ("Atlas", "Echo")
- Light gold: `#F4C99E` — Gold tint (business cards, premium badges)

### Status Colors (from Figma, used inline)

- Success: bg `#E5FFF9`, text `#53A329`, border `#53A329`
- Error: bg `#FFE9E5`, text `#8A220F`, border `#8A220F` / accent `#E55947`
- Warning: bg `#FFFAE5`, text `#614600`, border `#614600`
- Info: bg `#E5F3FF`, text `#1569B7`, border `#1569B7`
- Neutral: bg `#F2F2F2`, text `#454545`, border `#454545`

### Additional Colors (from Figma, not in token system)

- `#91A38F` — Gray-green border (location badges)
- `#109504` — Vivid green border (on-site status)
- `#59150D` — Deep red border (cancel buttons)

---

### Additional Colors (from deeper Figma exploration)

- `#354C28` — Dark green (website CTA button border)
- `#446540` — Medium dark green (business card tagline gradient)
- `#F2FBED` — Very light sage (Copilot background, active sidebar items)
- `#EDF9E7` — Light sage (radial glow endpoint, presentation bg)
- `#FCFEFB` — Near-white (navbar gradient endpoint)
- `#E6E6E6` — Neutral gray (bot message bubbles in chat)

---

## Typography

- **Family:** `'Afacad', sans-serif` — the app font. No exceptions in-app.
- **Marketing headlines:** `'Montserrat', sans-serif` 600 weight, 72px, -5% letter-spacing — service website hero only
- **Presentations:** `'PP Fragment'` 400/800 weight — slide decks only
- **Weights:** 400 (body), 500 (nav links/emphasis), 600 (headings), 700 (display/logo wordmark)
- **Line height:** `1.333em` consistently
- **Logo wordmark:** Afacad 700, 28px
- **Nav links:** Afacad 500, 18px, active `#1D241C`, inactive `#6F826A`
- **Scale:** 10, 12, 14 (base body), 15, 16, 18, 20, 24, 26, 28, 36, 40, 48px
- **Google Fonts import:** `https://fonts.googleapis.com/css2?family=Afacad:wght@400;500;600;700&display=swap`
- In the app: font is set globally — don't add `font-[Afacad]` per component

## Border Radius

From Figma, confirmed by codebase usage:

- `6px` — Badges, tags, small inputs, table cells
- `10px` — Panels, sections, containers (matches `--radius: 0.625rem`)
- `12px` — `rounded-xl` in Tailwind, sidebar items, context chips
- `16px` — `rounded-2xl`, input containers (AtlasInput)
- `20px` — Cards, modals, dialogs (Figma intent)
- `30px` — Buttons, pills
- `40px`+ — Hero containers, circular close buttons (`49px`)
- `9999px` — Avatars, fully circular elements

**Codebase note:** `Card` component uses `rounded-xl` which is ~14px, not the Figma-intended 20px. Accept this for in-app cards; use 20px for external/marketing.

---

## Shadows (Figma Effects)

All effects extracted from the Figma file:

```css
/* Card shadow — sage-tinted */
box-shadow: 0px 2px 6px rgba(187, 216, 163, 0.5);

/* Light ambient — acceptable gray */
box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.1);

/* Micro shadow */
box-shadow: 0px 2px 2px rgba(0, 0, 0, 0.05);

/* Stronger ambient */
box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.15);

/* Inner sage glow */
box-shadow: inset 0px 0px 8px rgba(187, 216, 163, 1);

/* Strong inner sage glow (business cards) */
box-shadow: inset 0px 0px 40px 0px rgba(187, 216, 163, 1);

/* Active element glow */
box-shadow: inset 0px 0px 9.4px rgba(83, 163, 41, 0.6);

/* Deep inner ambient */
box-shadow: inset 0px 4px 20px rgba(187, 216, 163, 0.3);

/* Inner ambient (subtle) */
box-shadow: inset 0px 0px 20px rgba(187, 216, 163, 0.4);

/* Dark overlay */
box-shadow: inset 0px 0px 20px rgba(29, 36, 28, 1);
box-shadow: 0px 0px 20px rgba(29, 36, 28, 1);

/* Glass surface (dark mode) */
box-shadow: inset 0px 2px 2px rgba(255, 255, 255, 0.15);

/* Neon accent point */
box-shadow: 0px 0px 2px rgba(115, 255, 0, 1);

/* Navbar bottom-edge sage glow (service website) */
box-shadow: inset 0px -16px 80px rgba(187, 216, 163, 0.2);

/* Feature card subtle inner glow (service website) */
box-shadow: inset 0px 0px 80px rgba(187, 216, 163, 0.25);

/* Feature card muted inner glow (alternate) */
box-shadow: inset 0px 0px 80px rgba(111, 130, 106, 0.5);

/* Connector hub glow (service website circuit pattern) */
box-shadow: 0px 0px 40px rgba(187, 216, 163, 1);

/* Mobile chat input glow */
box-shadow: 0px 0px 10px 0px rgba(187, 216, 163, 0.5);
```

---

## Gradients

```css
/* Accent glow border — active/analysis states */
linear-gradient(90deg, #B9F289, #82EA72, #3EB400, #00FFBF);

/* Card surface — subtle white-to-mint */
linear-gradient(135deg, #FFFFFF, #F9FDF7);

/* Subtle surface wash */
linear-gradient(90deg, #F9FDF7, #EDF9EC);

/* Social media template: Echo (top-down white-to-mint) */
linear-gradient(180deg, #FFFFFF, #F6FCF3);

/* Social media template: Atlas (bottom-up mint-to-white) */
linear-gradient(0deg, #F6FCF3, #FFFFFF);

/* Dark header / login gradient */
linear-gradient(180deg, #1D241C, #3A4838);

/* Business card tagline gradient */
linear-gradient(0deg, #1D241C, #446540);

/* Sage fade bar */
linear-gradient(-90deg, rgba(187,216,163,0), #BBD8A3 20%, #BBD8A3 80%, rgba(111,130,106,0));

/* Patient landing — white to sage */
linear-gradient(180deg, #FFFFFF 0%, #EEF7E8 60%, #BBD8A3 100%);

/* Radial card glow */
radial-gradient(circle at 50% 50%, #FFFFFF, #F2F7ED);

/* Business card front glow */
radial-gradient(circle at 50% 50%, #F6FCF3, #EDF9E7);

/* Navbar surface (service website) — mint to near-white */
linear-gradient(0deg, #F6FCF3, #FCFEFB);

/* Copilot surface — light sage to near-white */
linear-gradient(180deg, #F2FBED, #F9FDF7);

/* Mobile chat surface */
linear-gradient(180deg, #FFFFFF, #F9FDF7);

/* Presentation slide background (variants) */
linear-gradient(180deg, #F6FCF3, #EDF9E7);  /* standard */
linear-gradient(180deg, #EDF9E7, #F6FCF3);  /* inverted */
linear-gradient(-90deg, #F6FCF3, #EDF9E7);  /* horizontal */

/* Presentation title gradient text (green to dark) */
linear-gradient(0deg, #53A329, #1D241C);

/* Contact page radial */
radial-gradient(circle at 50% 50%, #FCFEFB, #F0FBEB);

/* Status card gradients */
linear-gradient(180deg, #DEF7DE, white);  /* completed */
linear-gradient(180deg, #F9E7E7, white);  /* cancelled */

/* Mobile canvas — subtle radial (color palette display) */
radial-gradient(circle at 50% 50%, rgba(246, 252, 243, 1) 0%, rgba(215, 232, 201, 1) 100%);
/* i.e. #F6FCF3 → #D7E8C9 — the two endpoints of the sage scale */

/* Social template Echo — BG vector (sage to teal) */
linear-gradient(180deg, #BBD8A3 0%, #93E9E2 100%);

/* Social template Atlas — BG vector (dark to muted green) */
linear-gradient(180deg, #1D241C 0%, #6F826A 100%);

/* Copilot desktop app — gradient border stroke (0.5px) */
linear-gradient(180deg, rgba(255, 255, 255, 1) 0%, rgba(246, 252, 243, 1) 100%);
/* applied as a 0.5px strokeWeight gradient border on the desktop app frame */
```

---

## Component Patterns

### Buttons (codebase reality)

The `Button` component (`ui/button.tsx`) uses CVA variants. Prefer these over custom styles:
- `default` — sage background, dark text
- `destructive` — red background, white text
- `outline` — bordered, subtle background
- `secondary` — light background
- `ghost` — transparent, hover accent
- `loginGradient` — dark gradient for login page

**Figma intent** (for external/marketing use):
- Primary CTA: `bg-[#53A329] text-white rounded-[30px] hover:bg-[#317128]`
- Secondary: `bg-[#E7F7DE] text-[#2C7326] border border-[#BBD8A3] rounded-[30px]`
- Ghost: `transparent text-[#6F826A] hover:bg-[#F0FAEB]`

### Cards

In-app: Use `<Card>` component (rounded-xl, border, shadow-sm). For status-specific styling, apply `style={{}}` for background/border overrides (see `ConsultationCard` pattern).

### Active/Analysis State

Animated gradient border used for AI processing:
- CSS class `border-glow-analysis` wraps the neon gradient
- `drop-shadow-analysis` adds multi-layer green luminescence
- `TextShimmer` component for pulsing text during analysis

### Active Sidebar Item

```
bg-gradient-to-b from-[#f2fbed] to-[#f9fdf7] border border-[#bbd8a3]
```

### Context Chips (Atlas)

```
inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-[#f2fbed] border border-[#bbd8a3] text-xs font-medium text-foreground
```

### Service Website (pharmia.ca) Patterns

Navbar:
- Surface: `linear-gradient(0deg, #F6FCF3, #FCFEFB)` with bottom 1px `#BBD8A3` border
- Inner glow: `inset 0px -16px 80px rgba(187, 216, 163, 0.2)` — sage bleeds upward from bottom edge
- Logo: Pharmia wordmark, Afacad 700, 28px, `#1D241C`
- Nav links: Afacad 500, 18px, active `#1D241C`, inactive `#6F826A`, 40px gap
- CTA buttons: 8px radius (!), two styles — "Contact" (white bg, `#1D241C` 1px border) and "Essaye" (`#1D241C` bg, `#354C28` border)

Section tags (pills):
- Border: 1px `#1D241C`, radius 40px, padding 8px 24px
- Text: Afacad 600, 20px, -5% letter-spacing

Feature cards:
- White bg with `#BBD8A3` 1px border, 10px radius
- Inner glow: `inset 0px 0px 80px rgba(187, 216, 163, 0.25)` — very subtle
- Alternate: `#1D241C` text on dark, `#6F826A` 1px border, `inset 0px 0px 80px rgba(111, 130, 106, 0.5)`

Banner/Footer: `#1D241C` dark background

### Mobile Chat Patterns (Figma 428x941)

- Surface: `linear-gradient(180deg, #FFFFFF, #F9FDF7)`
- Chat header: Row — back arrow (42px circle, `#BBD8A3` bg, 49px radius), title stack (label 16px `#6F826A`, condition 20px `#1D241C`), close button (42px circle, `#1D241C` bg, `#F6FCF3` icon)
- Separator: 1px `#BBD8A3` line
- Message bubbles: 8px radius — user messages `#BBD8A3` bg, bot messages `#E6E6E6` bg
- Input bar: White bg, 1px `#BBD8A3` border, **70px radius**, padding 16px 20px, sage glow shadow `0px 0px 10px rgba(187, 216, 163, 0.5)`
- Placeholder: Afacad 400, 18px, `#6F826A`
- Body area: 12px radius, 12px padding

### Copilot Patterns

- Surface: `linear-gradient(180deg, #F2FBED, #F9FDF7)` with white overlay
- Desktop app: 1549x944 frames

### Updated Dashboard — Screens Inventory

All screens are 1920×1080. Background fill `#F6FCF3`. The Updated Dashboard frame (`2739:647`) contains:

| Frame | Node | Description |
|---|---|---|
| Advice | `2884:603` | Advice/consultation list — What's New, In Progress, Closed states |
| Kanban | `2884:620` | GitHub-style kanban board view |
| Drawer | `2884:601` | Pharmacist detail drawer (5 states: Drawer 1–5) |
| Settings | `2884:608` | Settings — User, Profile, Facturation sub-pages |
| Module Sidebar | `3991:252` | Sidebar in two states: Opened (1875×921) and Closed (1875×922) |
| Patient view | `2884:611` | Patient detail — mobile (428px) and desktop (1920px) variants |
| Onboarding: EN | `2884:617` | 10-step onboarding flow (creating a consultation) |
| Pharmia Écho Dashboard | `3235:41` | Echo login + verification pages |

**Sidebar states**: Use Opened (`3991:223`, 1875×921) vs Closed (`3991:239`, 1875×922) as reference for collapsed/expanded sidebar design.

---

## External Asset Templates (from Figma)

### Business Cards (node `4094:147`)

- Size: 726 x 415px
- Background: white with `#F6FCF3` fill and large sage logo watermark at 10% opacity
- Name: Afacad 600 (semibold), 36px
- Title: Afacad 400, 20px
- Tagline: "La plateforme IA tout-en-un pour la pharmacie quebecoise." — gradient text `linear-gradient(0deg, #1D241C, #446540)`
- Front face: radial gradient glow `radial-gradient(circle, #F6FCF3, #EDF9E7)` with inner sage shadow

### Social Media Templates (node `4188:128`)

- Size: 555 x 728px
- Echo template: `linear-gradient(180deg, #FFFFFF, #F6FCF3)`
- Atlas template: `linear-gradient(0deg, #F6FCF3, #FFFFFF)`
- Content padding: 40px horizontal, 32px vertical
- 16px gap between elements

### Brand Color Palette Strip

Six swatches used across cards and marketing:
- `#F4C99E` (light gold)
- `#BF9264` (gold)
- `#F6FCF3` (mint bg — implied, palette position)
- `#BBD8A3` (sage)
- `#6F826A` (muted green)
- `#1D241C` (forest dark)

---

## Rules

1. **Reuse existing components.** Check `ui/` first. Near-zero new primitives.
2. **Use CSS variables.** `text-foreground` not `text-[#1d241c]`. Only hardcode for values not in the token system.
3. **Afacad in-app.** Never use Inter, Roboto, system fonts in the app. Don't add `font-[Afacad]` in-app — it's already global. Exceptions: Montserrat for marketing hero headings, PP Fragment for slide decks.
4. **Green shadows only.** Use the HSL shadow scale or sage-tinted shadows. Never gray shadows alone.
5. **No pure black or white.** `#1D241C` instead of `#000`. `#F6FCF3` instead of `#FFF` for backgrounds.
6. **French-first.** All UI strings through `t()`. Never hardcode text in JSX.
7. **Sage is the brand.** `#BBD8A3` for glows, highlights, focus rings, borders.
8. **Gold for product names.** "Atlas", "Echo" in `text-brand` (`#BF9264`).
9. **Green luminescence for emphasis.** Neon gradient (`#B9F289 -> #00FFBF`) for active states, not blue/purple.
10. **Dark mode is forest.** When implemented: forest-green tinted backgrounds, never pure gray.
11. **Don't break what exists.** No `window.location.reload()`, no side-effects on unrelated components.
12. **Mobile-first.** Test at 430px. Adapt, don't just shrink.
13. **No overfit.** Fix the pattern, not just the symptom. Don't add unnecessary elements.
14. **Contrast-check all states.** Verify text is readable on its background in default, hover, active, focus, and disabled states. White text on light Pharmia surfaces is invisible. Audit third-party CSS variable chains for state overrides that assume dark backgrounds.

## Figma Source

- File key: `3wO37CgmyZLjhrTdFrMyOr`
- Canvases:
  - Pharmia: `0:1`
  - Pharmia Mobile: `3751:26`
  - Pharmia Echo: `3458:300`
  - Updated Dashboard: `3458:302` (Mobile: `3458:11916`, Desktop: `3458:12519`, Logo: `3464:165`)
  - Pharmia Copilot: `3458:301`
  - Copilot Desktop App: `3464:215` (frames: `3571:90`)
  - Service website: `841:26`
  - Templates Réseaux: `4188:128`
  - Carte d'affaire: `4094:147`
  - Brochure: `3287:41`
  - PROJET TERMINUS: `4250:6` (single image frame — Agentic mode 1, not UI)
- Updated Dashboard (main app): `2739:647`
- Old Dashboard group: `1818:28`
- Mobile chat frame: `3809:26` (428×941)
- Service website V1: `3998:29` / V2: `3999:2671`
- Business cards: `4094:147`
- Social media templates: `4188:128`
