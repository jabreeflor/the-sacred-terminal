import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.dirname(fileURLToPath(import.meta.url));
const iconsDir = path.join(root, 'assets/icons');
const map = {
  claude: 'claude-color',
  codex: 'openai-color',
  cursor: 'cursor-color',
  gemini: 'gemini-color',
  copilot: 'copilot-color',
  opencode: 'cline-color',
  shell: 'shell-color',
};

function inner(file) {
  const svg = fs.readFileSync(path.join(iconsDir, file + '.svg'), 'utf8');
  return svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').replace(/\s+/g, ' ').trim();
}

const pickerEntries = Object.entries(map)
  .map(([k, v]) => `    ${k}: ${JSON.stringify(inner(v))}`)
  .join(',\n');

const out = `/* Brand + UI icons — vendored Lobe Icons SVGs (lobehub/lobe-icons). */
(function (global) {
  var BASE = 'assets/icons/';
  var CACHE = 'v=5';

  var AGENT_META = {
    claude:   { file: 'claude-color.svg',  label: 'Claude Code',  mono: false },
    codex:    { file: 'openai-color.svg',  label: 'OpenAI Codex', mono: false },
    cursor:   { file: 'cursor-color.svg',  label: 'Cursor Agent', mono: false },
    gemini:   { file: 'gemini-color.svg',  label: 'Gemini',       mono: false },
    copilot:  { file: 'copilot-color.svg', label: 'Copilot',      mono: false },
    opencode: { file: 'cline-color.svg',   label: 'OpenCode',     mono: false },
    shell:    { file: 'shell-color.svg',   label: 'Shell',        mono: false },
  };

  var PICKER_SVG = {
${pickerEntries}
  };

  function svg(size, vb, inner, attrs) {
    attrs = attrs || '';
    return '<svg width="' + size + '" height="' + size + '" viewBox="' + vb + '" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"' + attrs + '>' + inner + '</svg>';
  }

  function claudePixel(size) {
    return svg(size, '0 0 16 14',
      '<rect x="1" y="0" width="14" height="14" rx="2" fill="#cc785c"/>' +
      '<rect x="3" y="3" width="2" height="2" fill="#fff"/>' +
      '<rect x="11" y="3" width="2" height="2" fill="#fff"/>' +
      '<rect x="5" y="7" width="6" height="1.5" fill="#fff"/>' +
      '<rect x="4" y="10" width="2" height="2" fill="#fff"/>' +
      '<rect x="10" y="10" width="2" height="2" fill="#fff"/>');
  }

  function dragHandle(size, color) {
    color = color || 'currentColor';
    return svg(size, '0 0 24 24',
      '<circle cx="9" cy="7" r="1.3" fill="' + color + '" opacity=".45"/>' +
      '<circle cx="15" cy="7" r="1.3" fill="' + color + '" opacity=".45"/>' +
      '<circle cx="9" cy="12" r="1.3" fill="' + color + '" opacity=".45"/>' +
      '<circle cx="15" cy="12" r="1.3" fill="' + color + '" opacity=".45"/>' +
      '<circle cx="9" cy="17" r="1.3" fill="' + color + '" opacity=".45"/>' +
      '<circle cx="15" cy="17" r="1.3" fill="' + color + '" opacity=".45"/>');
  }

  function folderClosed(size, color) {
    color = color || 'currentColor';
    return svg(size, '0 0 24 24',
      '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z" fill="' + color + '" opacity=".22" stroke="' + color + '" stroke-width="1.2" stroke-linejoin="round"/>');
  }

  function folderOpen(size, color) {
    color = color || 'currentColor';
    return svg(size, '0 0 24 24',
      '<path d="M3 16l2.5-7H22l-2.4 7a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z" fill="' + color + '" opacity=".28" stroke="' + color + '" stroke-width="1.2" stroke-linejoin="round"/>' +
      '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2" stroke="' + color + '" stroke-width="1.2" stroke-linejoin="round" opacity=".55"/>');
  }

  function plus(size, color) {
    color = color || 'currentColor';
    return svg(size, '0 0 24 24',
      '<path d="M12 5v14M5 12h14" stroke="' + color + '" stroke-width="2" stroke-linecap="round"/>');
  }

  function spinner(size, color) {
    color = color || 'currentColor';
    return svg(size, '0 0 24 24',
      '<circle cx="12" cy="12" r="9" stroke="' + color + '" stroke-width="2.2" stroke-opacity=".18" fill="none"/>' +
      '<path d="M12 3a9 9 0 0 1 9 9" stroke="' + color + '" stroke-width="2.2" stroke-linecap="round" fill="none">' +
      '<animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.85s" repeatCount="indefinite"/></path>');
  }

  function agentIcon(key, size) {
    size = size || 14;
    var meta = AGENT_META[key] || AGENT_META.shell;
    if (!meta.file) return '';
    var cls = 'agent-brand' + (meta.mono ? ' agent-brand--mono' : '');
    return '<img class="' + cls + '" src="' + BASE + meta.file + '?' + CACHE + '" width="' + size + '" height="' + size + '" alt="' + meta.label + '" draggable="false"/>';
  }

  /* Inline brand marks for picker — avoids img+cache issues and gradient breakage. */
  function agentIconPicker(key, size) {
    size = size || 20;
    var meta = AGENT_META[key] || AGENT_META.shell;
    var inner = PICKER_SVG[key] || PICKER_SVG.shell;
    var fill = key === 'codex' ? ' fill="#10A37F"' : key === 'cursor' ? ' fill="#8CAAEE"' : '';
    return '<svg class="agent-brand agent-brand--inline" width="' + size + '" height="' + size + '" viewBox="0 0 24 24"' + fill + ' xmlns="http://www.w3.org/2000/svg" role="img" aria-label="' + meta.label + '">' + inner + '</svg>';
  }

  function sessionIcon(key, size, status) {
    if (status === 'working' || status === 'waiting') {
      var c = status === 'waiting' ? '#e5c890' : '#a6d189';
      return spinner(size || 13, c);
    }
    return agentIcon(key, size);
  }

  global.SacredIcons = {
    agentIcon: agentIcon,
    agentIconPicker: agentIconPicker,
    sessionIcon: sessionIcon,
    claudePixel: claudePixel,
    dragHandle: dragHandle,
    folderClosed: folderClosed,
    folderOpen: folderOpen,
    plus: plus,
    spinner: spinner,
  };
})(typeof window !== 'undefined' ? window : globalThis);
`;

fs.writeFileSync(path.join(root, 'icons.js'), out);
console.log('wrote icons.js', out.length, 'bytes');
