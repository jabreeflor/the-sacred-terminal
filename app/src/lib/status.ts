import type { Status } from '../types'

export interface StatusMeta {
  label: string
  color: string
  pulse: boolean
}

// Single source of truth for status treatment (spec §8). The rail dots, the
// terminal-tab spinners, and the menu-bar pulse all read from here, so a
// session looks consistent everywhere it appears.
export function statusMeta(status: Status): StatusMeta {
  switch (status) {
    case 'working':
      return { label: 'Working', color: '#a6d189', pulse: true }
    case 'waiting':
      return { label: 'Needs input', color: '#e5c890', pulse: true }
    case 'done':
      return { label: 'Done', color: '#8caaee', pulse: false }
    case 'idle':
    default:
      return { label: 'Idle', color: '#5b5b63', pulse: false }
  }
}
