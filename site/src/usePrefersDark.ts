import { useEffect, useState } from 'react'

/** Follows the viewer's light or dark appearance, as the Panel does on macOS. */
export function usePrefersDark() {
  const [dark, setDark] = useState(false)
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const update = () => setDark(mq.matches)
    update()
    mq.addEventListener('change', update)
    return () => mq.removeEventListener('change', update)
  }, [])
  return dark
}
