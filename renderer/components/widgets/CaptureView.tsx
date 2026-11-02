import React, { useRef, useState } from 'react'
import { motion } from 'motion/react'
import { Check, Inbox, Pencil, Trash2 } from 'lucide-react'
import { dragFile, openFile, type FileItem } from '../../hooks/useFiles'

/** The capture card's content height; the notch's size for it follows. */
export const CAPTURE_HEIGHT = 96
export const CAPTURE_WIDTH = 404

const spring = { type: 'spring' as const, stiffness: 420, damping: 26 }

/** Puts a file on the Shelf from outside it: the Shelf reads its list when shown. */
const keepOnShelf = async (file: string) => {
  const paths = ((await window.bridge?.invoke<string[]>('store:get', 'shelf')) ?? []).filter((p) => p !== file)
  await window.bridge?.invoke('store:set', 'shelf', [...paths, file])
}

/**
 * A screenshot, just taken: the macOS corner thumbnail, in the notch. It
 * lands with a flash, like a shutter. Drag it straight into a chat or a
 * folder, keep it on the Shelf for later, or open it; left alone, the notch
 * folds away and the file stays where macOS saved it. Dealt with (kept,
 * opened, dragged out), it calls `onDone` and the notch folds away at once.
 */
export const CaptureView: React.FC<{ item: FileItem; accent: string; onDone: () => void }> = ({ item, accent, onDone }) => {
  const [kept, setKept] = useState(false)
  // Renaming moves the file, so everything below acts on this path, not item.path.
  const [path, setPath] = useState(item.path)
  const stem = (p: string) => (p.split(/[\\/]/).pop() ?? '').replace(/\.[^.]+$/, '')
  const [name, setName] = useState(() => stem(item.path))
  const [editing, setEditing] = useState(false)
  // Refs, not state: the field's blur can fire again as it unmounts, and must
  // neither save twice nor save what Esc just threw away.
  const open = useRef(false)
  const cancelled = useRef(false)
  const startEditing = () => {
    open.current = true
    cancelled.current = false
    setEditing(true)
  }
  /** The field closes: saves what it holds, unless Esc closed it. */
  const finish = async (value: string) => {
    if (!open.current) return
    open.current = false
    setEditing(false)
    if (cancelled.current || value.trim() === stem(path)) return setName(stem(path))
    const next = await window.bridge?.invoke<string | null>('screenshot:rename', path, value)
    // Taken, empty or refused: the old name comes back.
    if (next) setPath(next)
    setName(stem(next ?? path))
  }

  return (
    <div className="flex h-full items-center gap-4" onClick={(event) => event.stopPropagation()}>
      <motion.div
        initial={{ scale: 0.7, rotate: -4, opacity: 0 }}
        animate={{ scale: 1, rotate: 0, opacity: 1 }}
        transition={spring}
        draggable
        onDragStart={(event) => {
          event.preventDefault()
          void dragFile(path, (event.target as HTMLElement).closest('main')).then((out) => out && onDone())
        }}
        onClick={() => {
          openFile(path)
          onDone()
        }}
        title="Click to open, or drag it into an app"
        className="relative shrink-0 cursor-grab overflow-hidden rounded-[12px] shadow-[0_0_0_1px_rgba(255,255,255,0.16),0_10px_24px_-10px_rgba(0,0,0,0.9)] active:cursor-grabbing"
        style={{ height: CAPTURE_HEIGHT }}
      >
        {item.thumb ? (
          <img src={item.thumb} alt="" draggable={false} className="h-full w-auto max-w-[160px] object-cover" />
        ) : (
          <div className="h-full w-[150px] bg-white/10" />
        )}
        {/* The shutter: a white flash that fades as the picture settles. */}
        <motion.div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-white"
          initial={{ opacity: 0.85 }}
          animate={{ opacity: 0 }}
          transition={{ duration: 0.45, ease: 'easeOut' }}
        />
      </motion.div>

      <motion.div
        className="flex min-w-0 flex-1 flex-col"
        initial={{ opacity: 0, x: -6 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ delay: 0.1, duration: 0.2 }}
      >
        {/* The name, with a pencil to rename it; renaming turns it into a field with its own Save. */}
        {editing ? (
          <div className="flex items-center gap-1">
            <input
              autoFocus
              value={name}
              aria-label="New name"
              spellCheck={false}
              onChange={(event) => setName(event.target.value)}
              onFocus={(event) => event.target.select()}
              onBlur={(event) => void finish(event.currentTarget.value)}
              onKeyDown={(event) => {
                if (event.key === 'Escape') cancelled.current = true
                if (event.key === 'Enter' || event.key === 'Escape') event.currentTarget.blur()
              }}
              className="h-[26px] w-full min-w-0 rounded-[8px] border border-white/20 bg-white/[0.08] px-2 text-[12px] font-medium text-white outline-none focus:border-white/40"
            />
            <button
              type="button"
              aria-label="Save name"
              title="Save (Enter)"
              // Pressing it takes focus from the field, and the field's blur saves.
              className="grid h-[26px] w-[26px] shrink-0 place-items-center rounded-full text-black"
              style={{ background: accent }}
            >
              <Check size={13} strokeWidth={2.6} />
            </button>
          </div>
        ) : (
          <div className="flex h-[26px] min-w-0 items-center gap-1.5">
            <span className="min-w-0 truncate text-[13px] font-semibold text-white" title={name}>
              {name}
            </span>
            <button
              type="button"
              aria-label="Rename"
              title="Rename"
              onClick={startEditing}
              className="grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full text-white/45 transition-colors hover:bg-white/[0.1] hover:text-white"
            >
              <Pencil size={11} strokeWidth={2.2} />
            </button>
          </div>
        )}
        <span className="mt-0.5 truncate text-[11px] text-white/45">{kept ? 'Saved. Find it anytime on the Shelf' : 'Save it to the Shelf to use later'}</span>
        <div className="mt-2.5 flex gap-1.5">
          <motion.button
            type="button"
            whileTap={{ scale: 0.94 }}
            onClick={() => {
              if (kept) return
              setKept(true)
              // A beat to see it land, then out of the way.
              void keepOnShelf(path).then(() => setTimeout(onDone, 650))
            }}
            className="flex h-[26px] shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3 text-[11px] font-medium transition-colors"
            style={kept ? { background: accent, color: '#000' } : { background: 'rgba(255,255,255,0.1)', color: 'rgba(255,255,255,0.85)' }}
          >
            {kept ? <Check size={12} strokeWidth={2.6} /> : <Inbox size={12} strokeWidth={2.2} />}
            {kept ? 'Saved' : 'Save to Shelf'}
          </motion.button>
          <motion.button
            type="button"
            whileTap={{ scale: 0.94 }}
            onClick={() => {
              openFile(path)
              onDone()
            }}
            className="h-[26px] shrink-0 whitespace-nowrap rounded-full bg-white/[0.06] px-3 text-[11px] font-medium text-white/60 transition-colors hover:bg-white/[0.12] hover:text-white"
          >
            Open
          </motion.button>
          {/* Not wanted: gone before it clutters the folder (to the Recycle Bin). */}
          {!kept && (
            <motion.button
              type="button"
              aria-label="Discard screenshot"
              title="Discard"
              whileTap={{ scale: 0.9 }}
              onClick={() => {
                void window.bridge?.invoke('screenshot:discard', path)
                onDone()
              }}
              className="grid h-[26px] w-[26px] shrink-0 place-items-center rounded-full bg-white/[0.06] text-white/50 transition-colors hover:bg-[#FF453A]/20 hover:text-[#FF453A]"
            >
              <Trash2 size={12} strokeWidth={2.2} />
            </motion.button>
          )}
        </div>
      </motion.div>
    </div>
  )
}
