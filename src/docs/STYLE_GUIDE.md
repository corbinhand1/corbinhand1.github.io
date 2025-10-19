# Nebula Creative - Style Guide & Developer Documentation

## Overview
This document provides guidance for developers and AI agents working on the Nebula Creative website. The codebase has been restructured for maximum maintainability and ease of editing.

## Project Structure

```
src/
├── components/           # Reusable React components
│   ├── StageManager/    # Stage Manager component
│   ├── ConfettiButton/  # Confetti button component  
│   ├── StickyNote/      # Sticky note component
│   └── UI/              # Other UI components
├── config/              # Configuration files
│   ├── design.ts        # Design tokens and styling
│   └── timing.ts        # Animation timing values
├── types/               # TypeScript type definitions
│   └── design.ts        # Component and design types
└── docs/                # Documentation
    └── STYLE_GUIDE.md   # This file
```

## Design System

### Colors
All colors are defined in `src/config/design.ts`:

```typescript
export const BRAND = {
  bgA: "#0a0f15",        // Primary background
  bgB: "#0e1421",        // Secondary background  
  postit: "#FFEB3B",     // Sticky note yellow
  ink: "#111111",        // Text color
  glass: "rgba(255,255,255,0.06)",  // Glass effect
  border: "rgba(255,255,255,0.12)", // Border color
  glow: "rgba(148, 197, 255, 0.25)", // Glow effect
}
```

### Typography
Custom font sizes using CSS `clamp()` for responsive scaling:

```typescript
fontSize: {
  'mobile-xs': 'clamp(9px, 2.5vw, 10px)',    // Stage Manager logs
  'mobile-sm': 'clamp(10px, 3vw, 12px)',     // Stage Manager title
  'mobile-base': 'clamp(12px, 3.5vw, 14px)', // Body text, buttons
  'mobile-lg': 'clamp(14px, 4vw, 16px)',     // Subheadings
  'mobile-xl': 'clamp(16px, 4.5vw, 18px)',   // Main headings
  'mobile-2xl': 'clamp(18px, 5vw, 22px)',    // Large headings
}
```

### Spacing
Consistent spacing values:

```typescript
spacing: {
  'mobile-xs': '4px',
  'mobile-sm': '8px', 
  'mobile-md': '12px',
  'mobile-lg': '16px',
  'mobile-xl': '20px',
}
```

## Components

### StageManager
**Location:** `src/components/StageManager/StageManager.tsx`

**Purpose:** Displays real-time stage cues and logs

**Props:**
- `clockMs: number` - Current time in milliseconds
- `announce: (msg: string) => void` - Function to announce new messages
- `isMobile: boolean` - Whether running on mobile device

**Easy Editing:**
- **Size:** Change `STAGE_MANAGER.mobile.width` in `design.ts`
- **Font:** Change `STAGE_MANAGER.mobile.fontSize` in `design.ts`
- **Position:** Modify `STAGE_MANAGER.container` classes
- **Colors:** Update `STAGE_MANAGER.title` and `STAGE_MANAGER.log` classes
- **Right-side positioning:** CSS overrides in `mobile-optimized.css` ensure Stage Manager stays on the right side at all screen sizes

### ConfettiButton
**Location:** `src/components/ConfettiButton/ConfettiButton.tsx`

**Purpose:** Cycles through different confetti effects when clicked

**Props:**
- `scheduleLandings: (items: LandingSpec[]) => void` - Function to schedule confetti landings
- `clockMs: number` - Current time in milliseconds  
- `onConfettiPressed: () => void` - Callback when button is pressed

**Easy Editing:**
- **Button Style:** Change `CONFETTI_BUTTON.base` classes in `design.ts`
- **Inactive Style:** Change `CONFETTI_BUTTON.inactive` classes in `design.ts`
- **Effects:** Modify the `effects` array in the component
- **Colors:** Update `CONFETTI_BUTTON.effects` in `design.ts`
- **Timing:** Adjust `CONFETTI_TIMING` values in `timing.ts`

### StickyNote
**Location:** `src/components/StickyNote/StickyNote.tsx`

**Purpose:** Displays handwritten sticky notes with realistic paper effects

**Props:**
- `text: string` - Text content to display
- `pos: { right: number; bottom: number; rot?: number }` - Position and rotation
- `className?: string` - Additional CSS classes

**Easy Editing:**
- **Size:** Change `STICKY_NOTE.mobile/tablet/desktop/large.width/height` in `design.ts`
- **Font:** Modify `STICKY_NOTE.font` class
- **Colors:** Update `STICKY_NOTE.colors` in `design.ts`
- **Position:** Change `pos` prop values
- **Responsive Scaling:** Sticky notes now scale smoothly across breakpoints:
  - **Mobile (≤767px)**: 100px × 100px
  - **Tablet (768px-1023px)**: 120px × 120px  
  - **Desktop (1024px-1279px)**: 140px × 140px
  - **Large (≥1280px)**: 160px × 160px

## Common Editing Tasks

### Changing Font Sizes
1. **Global:** Update font size values in `src/config/design.ts`
2. **Component-specific:** Modify the component's className

### Changing Colors
1. **Brand colors:** Update `BRAND` object in `src/config/design.ts`
2. **Component colors:** Modify component-specific color classes

### Changing Sizes/Spacing
1. **Global:** Update `spacing` values in `src/config/design.ts`
2. **Component-specific:** Modify Tailwind classes in component files

### Adding New Components
1. Create component directory: `src/components/NewComponent/`
2. Create component file: `NewComponent.tsx`
3. Create index file: `index.ts`
4. Add types to `src/types/design.ts`
5. Add design tokens to `src/config/design.ts`

## Development Workflow

### Local Development
```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run preview      # Preview production build
npm run deploy       # Build and deploy to GitHub Pages
```

### File Organization
- **Components:** One component per directory
- **Configuration:** Centralized in `src/config/`
- **Types:** All TypeScript types in `src/types/`
- **Documentation:** Keep this guide updated

### Best Practices
1. **Use design tokens** from `src/config/design.ts` instead of hardcoded values
2. **Follow naming conventions** - components use PascalCase, files use camelCase
3. **Keep components focused** - one responsibility per component
4. **Use TypeScript** - all components should have proper type definitions
5. **Test locally** - always test changes on the development server

## Troubleshooting

### Common Issues
1. **Import errors:** Check that all components have proper `index.ts` files
2. **Styling conflicts:** Use design tokens instead of hardcoded values
3. **Type errors:** Ensure all props are properly typed in `src/types/design.ts`

### Getting Help
- Check this style guide first
- Look at existing components for patterns
- Test changes on the local development server
- Use TypeScript for better error messages

## Future Maintenance

This codebase is designed to be:
- **Easy to edit** - clear component structure and design tokens
- **Consistent** - standardized patterns and naming
- **Maintainable** - well-documented and organized
- **Scalable** - easy to add new components and features

When making changes:
1. Follow the established patterns
2. Update this documentation if needed
3. Test thoroughly on mobile devices
4. Keep the design system consistent
