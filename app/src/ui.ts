import { create } from 'zustand'

// Ephemeral, NON-persisted UI state: which overlay is open, anchors, toast.
export type SettingsTab = 'agents' | 'git' | 'appearance'

interface Anchor {
  left: number
  top: number
  bottom: number
  right: number
  width: number
}

interface UiState {
  settingsOpen: boolean
  settingsTab: SettingsTab

  pickerOpen: boolean
  pickerProjectId: string | null
  pickerWorktree: boolean
  pickerAnchor: Anchor | null

  modalOpen: boolean
  modalMode: 'create' | 'import'

  projectMenuOpen: boolean
  projectMenuAnchor: Anchor | null

  toastMsg: string
  toastShow: boolean

  openSettings: (tab?: SettingsTab) => void
  closeSettings: () => void
  setSettingsTab: (tab: SettingsTab) => void

  openPicker: (projectId: string, anchor: Anchor) => void
  closePicker: () => void
  setPickerWorktree: (on: boolean) => void

  openModal: (mode: 'create' | 'import') => void
  closeModal: () => void

  openProjectMenu: (anchor: Anchor) => void
  closeProjectMenu: () => void

  showToast: (msg: string) => void
  hideToast: () => void

  closeAll: () => void
}

let toastTimer: ReturnType<typeof setTimeout> | undefined

export const useUi = create<UiState>((set) => ({
  settingsOpen: false,
  settingsTab: 'agents',
  pickerOpen: false,
  pickerProjectId: null,
  pickerWorktree: false,
  pickerAnchor: null,
  modalOpen: false,
  modalMode: 'create',
  projectMenuOpen: false,
  projectMenuAnchor: null,
  toastMsg: '',
  toastShow: false,

  openSettings: (tab = 'agents') => set({ settingsOpen: true, settingsTab: tab, pickerOpen: false, modalOpen: false, projectMenuOpen: false }),
  closeSettings: () => set({ settingsOpen: false }),
  setSettingsTab: (tab) => set({ settingsTab: tab }),

  openPicker: (projectId, anchor) => set({ pickerOpen: true, pickerProjectId: projectId, pickerAnchor: anchor, pickerWorktree: false, modalOpen: false, projectMenuOpen: false, settingsOpen: false }),
  closePicker: () => set({ pickerOpen: false }),
  setPickerWorktree: (on) => set({ pickerWorktree: on }),

  openModal: (mode) => set({ modalOpen: true, modalMode: mode, projectMenuOpen: false }),
  closeModal: () => set({ modalOpen: false }),

  openProjectMenu: (anchor) => set({ projectMenuOpen: true, projectMenuAnchor: anchor, pickerOpen: false, modalOpen: false, settingsOpen: false }),
  closeProjectMenu: () => set({ projectMenuOpen: false }),

  showToast: (msg) =>
    set(() => {
      clearTimeout(toastTimer)
      toastTimer = setTimeout(() => useUi.setState({ toastShow: false }), 2400)
      return { toastMsg: msg, toastShow: true }
    }),
  hideToast: () => set({ toastShow: false }),

  closeAll: () => set({ settingsOpen: false, pickerOpen: false, modalOpen: false, projectMenuOpen: false }),
}))
