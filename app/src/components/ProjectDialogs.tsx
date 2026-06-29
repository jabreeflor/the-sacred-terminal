import { useEffect, useState } from 'react'
import { useStore } from '../store'
import { useUi } from '../ui'

export function ProjectDialogs() {
  const projectMenuOpen = useUi((s) => s.projectMenuOpen)
  const projectMenuAnchor = useUi((s) => s.projectMenuAnchor)
  const closeProjectMenu = useUi((s) => s.closeProjectMenu)
  const modalOpen = useUi((s) => s.modalOpen)
  const modalMode = useUi((s) => s.modalMode)
  const openModal = useUi((s) => s.openModal)
  const closeModal = useUi((s) => s.closeModal)
  const addProject = useStore((s) => s.addProject)

  const [name, setName] = useState('')
  const [path, setPath] = useState('')

  useEffect(() => {
    if (modalOpen) {
      setName('')
      setPath('')
    }
  }, [modalOpen])

  const submit = () => {
    addProject(name, path)
    closeModal()
  }

  return (
    <>
      {projectMenuOpen && (
        <>
          <div className="scrim" onClick={closeProjectMenu} />
          <div
            className="project-menu"
            style={{
              left: projectMenuAnchor ? Math.min(projectMenuAnchor.right - 200, window.innerWidth - 210) : 80,
              top: projectMenuAnchor ? projectMenuAnchor.bottom + 6 : 60,
            }}
          >
            <button onClick={() => openModal('import')}>
              Import folder…
              <span>Choose an existing directory</span>
            </button>
            <button onClick={() => openModal('create')}>
              Create new project…
              <span>Name and path for a new folder</span>
            </button>
          </div>
        </>
      )}

      {modalOpen && (
        <>
          <div className="scrim" onClick={closeModal} />
          <div className="modal">
            <h3>{modalMode === 'import' ? 'Import folder' : 'Create project'}</h3>
            <label>Name</label>
            <input
              placeholder="my-project"
              autoComplete="off"
              value={name}
              autoFocus={modalMode !== 'import'}
              onChange={(e) => setName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') (e.currentTarget.nextElementSibling?.nextElementSibling as HTMLInputElement)?.focus()
              }}
            />
            <label>Path</label>
            <input
              placeholder={modalMode === 'import' ? '/home/user/existing-project' : '/home/user/my-project'}
              autoComplete="off"
              value={path}
              autoFocus={modalMode === 'import'}
              onChange={(e) => setPath(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') submit()
              }}
            />
            <div className="row">
              <button onClick={closeModal}>Cancel</button>
              <button className="primary" onClick={submit}>
                Add
              </button>
            </div>
          </div>
        </>
      )}
    </>
  )
}
