/* Brand + UI icons — vendored Lobe Icons SVGs (lobehub/lobe-icons). */
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
    claude: "<title>Claude</title><path d=\"M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z\" fill=\"#D97757\" fill-rule=\"nonzero\"></path>",
    codex: "<title>OpenAI</title><path d=\"M21.55 10.004a5.416 5.416 0 00-.478-4.501c-1.217-2.09-3.662-3.166-6.05-2.66A5.59 5.59 0 0010.831 1C8.39.995 6.224 2.546 5.473 4.838A5.553 5.553 0 001.76 7.496a5.487 5.487 0 00.691 6.5 5.416 5.416 0 00.477 4.502c1.217 2.09 3.662 3.165 6.05 2.66A5.586 5.586 0 0013.168 23c2.443.006 4.61-1.546 5.361-3.84a5.553 5.553 0 003.715-2.66 5.488 5.488 0 00-.693-6.497v.001zm-8.381 11.558a4.199 4.199 0 01-2.675-.954c.034-.018.093-.05.132-.074l4.44-2.53a.71.71 0 00.364-.623v-6.176l1.877 1.069c.02.01.033.029.036.05v5.115c-.003 2.274-1.87 4.118-4.174 4.123zM4.192 17.78a4.059 4.059 0 01-.498-2.763c.032.02.09.055.131.078l4.44 2.53c.225.13.504.13.73 0l5.42-3.088v2.138a.068.068 0 01-.027.057L9.9 19.288c-1.999 1.136-4.552.46-5.707-1.51h-.001zM3.023 8.216A4.15 4.15 0 015.198 6.41l-.002.151v5.06a.711.711 0 00.364.624l5.42 3.087-1.876 1.07a.067.067 0 01-.063.005l-4.489-2.559c-1.995-1.14-2.679-3.658-1.53-5.63h.001zm15.417 3.54l-5.42-3.088L14.896 7.6a.067.067 0 01.063-.006l4.489 2.557c1.998 1.14 2.683 3.662 1.529 5.633a4.163 4.163 0 01-2.174 1.807V12.38a.71.71 0 00-.363-.623zm1.867-2.773a6.04 6.04 0 00-.132-.078l-4.44-2.53a.731.731 0 00-.729 0l-5.42 3.088V7.325a.068.068 0 01.027-.057L14.1 4.713c2-1.137 4.555-.46 5.707 1.513.487.833.664 1.809.499 2.757h.001zm-11.741 3.81l-1.877-1.068a.065.065 0 01-.036-.051V6.559c.001-2.277 1.873-4.122 4.181-4.12.976 0 1.92.338 2.671.954-.034.018-.092.05-.131.073l-4.44 2.53a.71.71 0 00-.365.623l-.003 6.173v.002zm1.02-2.168L12 9.25l2.414 1.375v2.75L12 14.75l-2.415-1.375v-2.75z\"/>",
    cursor: "<title>Cursor</title><path d=\"M22.106 5.68L12.5.135a.998.998 0 00-.998 0L1.893 5.68a.84.84 0 00-.419.726v11.186c0 .3.16.577.42.727l9.607 5.547a.999.999 0 00.998 0l9.608-5.547a.84.84 0 00.42-.727V6.407a.84.84 0 00-.42-.726zm-.603 1.176L12.228 22.92c-.063.108-.228.064-.228-.061V12.34a.59.59 0 00-.295-.51l-9.11-5.26c-.107-.062-.063-.228.062-.228h18.55c.264 0 .428.286.296.514z\"/>",
    gemini: "<title>Gemini</title><path d=\"M20.616 10.835a14.147 14.147 0 01-4.45-3.001 14.111 14.111 0 01-3.678-6.452.503.503 0 00-.975 0 14.134 14.134 0 01-3.679 6.452 14.155 14.155 0 01-4.45 3.001c-.65.28-1.318.505-2.002.678a.502.502 0 000 .975c.684.172 1.35.397 2.002.677a14.147 14.147 0 014.45 3.001 14.112 14.112 0 013.679 6.453.502.502 0 00.975 0c.172-.685.397-1.351.677-2.003a14.145 14.145 0 013.001-4.45 14.113 14.113 0 016.453-3.678.503.503 0 000-.975 13.245 13.245 0 01-2.003-.678z\" fill=\"#3186FF\"></path><path d=\"M20.616 10.835a14.147 14.147 0 01-4.45-3.001 14.111 14.111 0 01-3.678-6.452.503.503 0 00-.975 0 14.134 14.134 0 01-3.679 6.452 14.155 14.155 0 01-4.45 3.001c-.65.28-1.318.505-2.002.678a.502.502 0 000 .975c.684.172 1.35.397 2.002.677a14.147 14.147 0 014.45 3.001 14.112 14.112 0 013.679 6.453.502.502 0 00.975 0c.172-.685.397-1.351.677-2.003a14.145 14.145 0 013.001-4.45 14.113 14.113 0 016.453-3.678.503.503 0 000-.975 13.245 13.245 0 01-2.003-.678z\" fill=\"url(#lobe-icons-gemini-fill-0)\"></path><path d=\"M20.616 10.835a14.147 14.147 0 01-4.45-3.001 14.111 14.111 0 01-3.678-6.452.503.503 0 00-.975 0 14.134 14.134 0 01-3.679 6.452 14.155 14.155 0 01-4.45 3.001c-.65.28-1.318.505-2.002.678a.502.502 0 000 .975c.684.172 1.35.397 2.002.677a14.147 14.147 0 014.45 3.001 14.112 14.112 0 013.679 6.453.502.502 0 00.975 0c.172-.685.397-1.351.677-2.003a14.145 14.145 0 013.001-4.45 14.113 14.113 0 016.453-3.678.503.503 0 000-.975 13.245 13.245 0 01-2.003-.678z\" fill=\"url(#lobe-icons-gemini-fill-1)\"></path><path d=\"M20.616 10.835a14.147 14.147 0 01-4.45-3.001 14.111 14.111 0 01-3.678-6.452.503.503 0 00-.975 0 14.134 14.134 0 01-3.679 6.452 14.155 14.155 0 01-4.45 3.001c-.65.28-1.318.505-2.002.678a.502.502 0 000 .975c.684.172 1.35.397 2.002.677a14.147 14.147 0 014.45 3.001 14.112 14.112 0 013.679 6.453.502.502 0 00.975 0c.172-.685.397-1.351.677-2.003a14.145 14.145 0 013.001-4.45 14.113 14.113 0 016.453-3.678.503.503 0 000-.975 13.245 13.245 0 01-2.003-.678z\" fill=\"url(#lobe-icons-gemini-fill-2)\"></path><defs><linearGradient gradientUnits=\"userSpaceOnUse\" id=\"lobe-icons-gemini-fill-0\" x1=\"7\" x2=\"11\" y1=\"15.5\" y2=\"12\"><stop stop-color=\"#08B962\"></stop><stop offset=\"1\" stop-color=\"#08B962\" stop-opacity=\"0\"></stop></linearGradient><linearGradient gradientUnits=\"userSpaceOnUse\" id=\"lobe-icons-gemini-fill-1\" x1=\"8\" x2=\"11.5\" y1=\"5.5\" y2=\"11\"><stop stop-color=\"#F94543\"></stop><stop offset=\"1\" stop-color=\"#F94543\" stop-opacity=\"0\"></stop></linearGradient><linearGradient gradientUnits=\"userSpaceOnUse\" id=\"lobe-icons-gemini-fill-2\" x1=\"3.5\" x2=\"17.5\" y1=\"13.5\" y2=\"12\"><stop stop-color=\"#FABC12\"></stop><stop offset=\".46\" stop-color=\"#FABC12\" stop-opacity=\"0\"></stop></linearGradient></defs>",
    copilot: "<title>Copilot</title><path d=\"M17.533 1.829A2.528 2.528 0 0015.11 0h-.737a2.531 2.531 0 00-2.484 2.087l-1.263 6.937.314-1.08a2.528 2.528 0 012.424-1.833h4.284l1.797.706 1.731-.706h-.505a2.528 2.528 0 01-2.423-1.829l-.715-2.453z\" fill=\"url(#lobe-icons-copilot-fill-0)\" transform=\"translate(0 1)\"></path><path d=\"M6.726 20.16A2.528 2.528 0 009.152 22h1.566c1.37 0 2.49-1.1 2.525-2.48l.17-6.69-.357 1.228a2.528 2.528 0 01-2.423 1.83h-4.32l-1.54-.842-1.667.843h.497c1.124 0 2.113.75 2.426 1.84l.697 2.432z\" fill=\"url(#lobe-icons-copilot-fill-1)\" transform=\"translate(0 1)\"></path><path d=\"M15 0H6.252c-2.5 0-4 3.331-5 6.662-1.184 3.947-2.734 9.225 1.75 9.225H6.78c1.13 0 2.12-.753 2.43-1.847.657-2.317 1.809-6.359 2.713-9.436.46-1.563.842-2.906 1.43-3.742A1.97 1.97 0 0115 0\" fill=\"url(#lobe-icons-copilot-fill-2)\" transform=\"translate(0 1)\"></path><path d=\"M15 0H6.252c-2.5 0-4 3.331-5 6.662-1.184 3.947-2.734 9.225 1.75 9.225H6.78c1.13 0 2.12-.753 2.43-1.847.657-2.317 1.809-6.359 2.713-9.436.46-1.563.842-2.906 1.43-3.742A1.97 1.97 0 0115 0\" fill=\"url(#lobe-icons-copilot-fill-3)\" transform=\"translate(0 1)\"></path><path d=\"M9 22h8.749c2.5 0 4-3.332 5-6.663 1.184-3.948 2.734-9.227-1.75-9.227H17.22c-1.129 0-2.12.754-2.43 1.848a1149.2 1149.2 0 01-2.713 9.437c-.46 1.564-.842 2.907-1.43 3.743A1.97 1.97 0 019 22\" fill=\"url(#lobe-icons-copilot-fill-4)\" transform=\"translate(0 1)\"></path><path d=\"M9 22h8.749c2.5 0 4-3.332 5-6.663 1.184-3.948 2.734-9.227-1.75-9.227H17.22c-1.129 0-2.12.754-2.43 1.848a1149.2 1149.2 0 01-2.713 9.437c-.46 1.564-.842 2.907-1.43 3.743A1.97 1.97 0 019 22\" fill=\"url(#lobe-icons-copilot-fill-5)\" transform=\"translate(0 1)\"></path><defs><radialGradient cx=\"85.44%\" cy=\"100.653%\" fx=\"85.44%\" fy=\"100.653%\" gradientTransform=\"scale(-.8553 -1) rotate(50.927 2.041 -1.946)\" id=\"lobe-icons-copilot-fill-0\" r=\"105.116%\"><stop offset=\"9.6%\" stop-color=\"#00AEFF\"></stop><stop offset=\"77.3%\" stop-color=\"#2253CE\"></stop><stop offset=\"100%\" stop-color=\"#0736C4\"></stop></radialGradient><radialGradient cx=\"18.143%\" cy=\"32.928%\" fx=\"18.143%\" fy=\"32.928%\" gradientTransform=\"scale(.8897 1) rotate(52.069 .193 .352)\" id=\"lobe-icons-copilot-fill-1\" r=\"95.612%\"><stop offset=\"0%\" stop-color=\"#FFB657\"></stop><stop offset=\"63.4%\" stop-color=\"#FF5F3D\"></stop><stop offset=\"92.3%\" stop-color=\"#C02B3C\"></stop></radialGradient><radialGradient cx=\"82.987%\" cy=\"-9.792%\" fx=\"82.987%\" fy=\"-9.792%\" gradientTransform=\"scale(-1 -.9441) rotate(-70.872 .142 1.17)\" id=\"lobe-icons-copilot-fill-4\" r=\"140.622%\"><stop offset=\"6.6%\" stop-color=\"#8C48FF\"></stop><stop offset=\"50%\" stop-color=\"#F2598A\"></stop><stop offset=\"89.6%\" stop-color=\"#FFB152\"></stop></radialGradient><linearGradient id=\"lobe-icons-copilot-fill-2\" x1=\"39.465%\" x2=\"46.884%\" y1=\"12.117%\" y2=\"103.774%\"><stop offset=\"15.6%\" stop-color=\"#0D91E1\"></stop><stop offset=\"48.7%\" stop-color=\"#52B471\"></stop><stop offset=\"65.2%\" stop-color=\"#98BD42\"></stop><stop offset=\"93.7%\" stop-color=\"#FFC800\"></stop></linearGradient><linearGradient id=\"lobe-icons-copilot-fill-3\" x1=\"45.949%\" x2=\"50%\" y1=\"0%\" y2=\"100%\"><stop offset=\"0%\" stop-color=\"#3DCBFF\"></stop><stop offset=\"24.7%\" stop-color=\"#0588F7\" stop-opacity=\"0\"></stop></linearGradient><linearGradient id=\"lobe-icons-copilot-fill-5\" x1=\"83.507%\" x2=\"83.453%\" y1=\"-6.106%\" y2=\"21.131%\"><stop offset=\"5.8%\" stop-color=\"#F8ADFA\"></stop><stop offset=\"70.8%\" stop-color=\"#A86EDD\" stop-opacity=\"0\"></stop></linearGradient></defs>",
    opencode: "<title>OpenCode</title><path d=\"M17.035 3.991c2.75 0 4.98 2.24 4.98 5.003v1.667l1.45 2.896a1.01 1.01 0 01-.002.909l-1.448 2.864v1.668c0 2.762-2.23 5.002-4.98 5.002H7.074c-2.751 0-4.98-2.24-4.98-5.002V17.33l-1.48-2.855a1.01 1.01 0 01-.003-.927l1.482-2.887V8.994c0-2.763 2.23-5.003 4.98-5.003h9.962z\" fill=\"#9B87F5\"/><path d=\"M8.265 9.6a2.274 2.274 0 00-2.274 2.274v4.042a2.274 2.274 0 004.547 0v-4.042A2.274 2.274 0 008.265 9.6zm7.326 0a2.274 2.274 0 00-2.274 2.274v4.042a2.274 2.274 0 104.548 0v-4.042A2.274 2.274 0 0015.59 9.6z\" fill=\"#C4B5FD\"/><path d=\"M12.054 5.558a2.779 2.779 0 100-5.558 2.779 2.779 0 000 5.558z\" fill=\"#E9D5FF\"/>",
    shell: "<title>Shell</title><path d=\"M5 7l5 4-5 4\" stroke=\"#81C8BE\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/><path d=\"M12 17h7\" stroke=\"#A6D189\" stroke-width=\"2\" stroke-linecap=\"round\"/>"
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
