import { useUi } from '../ui'

export function Toast() {
  const msg = useUi((s) => s.toastMsg)
  const show = useUi((s) => s.toastShow)
  return <div className={'proto-toast' + (show ? ' show' : '')}>{msg}</div>
}
