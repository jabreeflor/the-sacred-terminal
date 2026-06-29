import type { ITheme } from '../lib/ghostty'

export interface GhosttyThemeDef {
  label: string
  /** ghostty config line shown in the Appearance pane. */
  config: string
  /** 4-color gradient swatch. */
  swatch: [string, string, string, string]
  theme: ITheme
}

// Ghostty's bundled themes, imported verbatim into ghostty-web's ITheme shape
// (spec §9). Swapping the active key re-skins every terminal pane at once.
export const GHOSTTY_THEMES: Record<string, GhosttyThemeDef> = {
  'catppuccin-frappe': {
    label: 'Catppuccin Frappé',
    config: 'theme = "catppuccin-frappe"',
    swatch: ['#303446', '#8caaee', '#a6d189', '#e78284'],
    theme: {
      background: '#303446', foreground: '#c6d0f5', cursor: '#f2d5cf', selectionBackground: '#626880',
      black: '#51576d', red: '#e78284', green: '#a6d189', yellow: '#e5c890',
      blue: '#8caaee', magenta: '#f4b8e4', cyan: '#81c8be', white: '#a5adce',
      brightBlack: '#626880', brightRed: '#e67172', brightGreen: '#8ec772', brightYellow: '#d9ba73',
      brightBlue: '#7b9ef0', brightMagenta: '#f2a4db', brightCyan: '#5abfb5', brightWhite: '#b5bfe2',
    },
  },
  'catppuccin-mocha': {
    label: 'Catppuccin Mocha',
    config: 'theme = "catppuccin-mocha"',
    swatch: ['#1e1e2e', '#89b4fa', '#a6e3a1', '#f38ba8'],
    theme: {
      background: '#1e1e2e', foreground: '#cdd6f4', cursor: '#f5e0dc', selectionBackground: '#45475a',
      black: '#45475a', red: '#f38ba8', green: '#a6e3a1', yellow: '#f9e2af',
      blue: '#89b4fa', magenta: '#f5c2e7', cyan: '#94e2d5', white: '#bac2de',
      brightBlack: '#585b70', brightRed: '#f37799', brightGreen: '#94e2d5', brightYellow: '#f5d080',
      brightBlue: '#7aa2f7', brightMagenta: '#f0a6d8', brightCyan: '#7bdac8', brightWhite: '#a6adc8',
    },
  },
  'catppuccin-macchiato': {
    label: 'Catppuccin Macchiato',
    config: 'theme = "catppuccin-macchiato"',
    swatch: ['#24273a', '#8aadf4', '#a6da95', '#ed8796'],
    theme: {
      background: '#24273a', foreground: '#cad3f5', cursor: '#f4dbd6', selectionBackground: '#494d64',
      black: '#494d64', red: '#ed8796', green: '#a6da95', yellow: '#eed49f',
      blue: '#8aadf4', magenta: '#f5bde6', cyan: '#8bd5ca', white: '#b8c0e0',
      brightBlack: '#5b6078', brightRed: '#e78284', brightGreen: '#8bd5a0', brightYellow: '#e5c890',
      brightBlue: '#7aa2f7', brightMagenta: '#f0a6d8', brightCyan: '#7bdac8', brightWhite: '#a5adce',
    },
  },
  'rose-pine-moon': {
    label: 'Rosé Pine Moon',
    config: 'theme = "rose-pine-moon"',
    swatch: ['#232136', '#9ccfd8', '#3e8fb0', '#eb6f92'],
    theme: {
      background: '#232136', foreground: '#e0def4', cursor: '#e0def4', selectionBackground: '#44415a',
      black: '#393552', red: '#eb6f92', green: '#3e8fb0', yellow: '#f6c177',
      blue: '#9ccfd8', magenta: '#c4a7e7', cyan: '#9ccfd8', white: '#e0def4',
      brightBlack: '#6e6a86', brightRed: '#f28cab', brightGreen: '#9ccfd8', brightYellow: '#f9d49a',
      brightBlue: '#c4a7e7', brightMagenta: '#ea9a97', brightCyan: '#b5e8e0', brightWhite: '#908caa',
    },
  },
  'gruvbox-dark': {
    label: 'Gruvbox Dark',
    config: 'theme = "gruvbox-dark"',
    swatch: ['#282828', '#83a598', '#b8bb26', '#fb4934'],
    theme: {
      background: '#282828', foreground: '#ebdbb2', cursor: '#ebdbb2', selectionBackground: '#504945',
      black: '#928374', red: '#fb4934', green: '#b8bb26', yellow: '#fabd2f',
      blue: '#83a598', magenta: '#d3869b', cyan: '#8ec07c', white: '#ebdbb2',
      brightBlack: '#665c54', brightRed: '#cc241d', brightGreen: '#98971a', brightYellow: '#d79921',
      brightBlue: '#458588', brightMagenta: '#b16286', brightCyan: '#689d6a', brightWhite: '#a89984',
    },
  },
}

export const DEFAULT_GHOSTTY_THEME = 'catppuccin-frappe'
