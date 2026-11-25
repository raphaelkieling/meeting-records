import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import {
  AudioLines, ArrowLeft, ArrowUp, Check, CircleHelp, CodeXml, Copy, House, Settings as SettingsIcon, Tag,
  Mic, MoreHorizontal, Orbit, Pause, Play, Plus, Search, Sparkles, Square, Users, X,
} from 'lucide-react'
import { meetings as seed, formatTime, toSeconds, liveLines } from './meetings'
import { Home, Label, Labels, Settings, colors } from './WorkspacePages'
import './style.css'

const icons = { spark: Sparkles, orbit: Orbit, code: CodeXml, mic: Mic, people: Users, wave: AudioLines }
const initialLabels = seed.map(({ label, color }) => ({ id: label, name: label, color }))
const navigation = [['Home', House], ['Labels', Tag], ['Settings', SettingsIcon]]
const tabs = ['Transcription', 'Summary', 'Inputs']
const wave = [20, 34, 26, 48, 63, 42, 76, 94, 65, 52, 72, 43, 33, 58, 70, 45, 30, 51, 26, 15, 40, 28, 17, 31, 16, 25, 14]

function Badge({ color, icon, shape = '' }) {
  const Icon = icons[icon]
  return <span aria-hidden="true" className={`badge ${color} ${shape}`}><Icon /></span>
}

function IconButton({ icon: Icon, label, className = '', ...props }) {
  return <button className={`icon-button ${className}`} aria-label={label} title={label} {...props}><Icon /></button>
}

function App() {
  const [meetings, setMeetings] = useState(() => seed.map((item) => ({ ...item, labels: [item.label] })))
  const [selected, setSelected] = useState(null)
  const [page, setPage] = useState('Home')
  const [labels, setLabels] = useState(initialLabels)
  const [filter, setFilter] = useState('')
  const [settings, setSettings] = useState({ microphone: 'System default', model: 'Whisper Small', timestamps: true })
  const [tab, setTab] = useState(tabs[0])
  const [searching, setSearching] = useState(false)
  const [query, setQuery] = useState('')
  const [editing, setEditing] = useState(null)
  const [menu, setMenu] = useState(false)
  const [mobileDetail, setMobileDetail] = useState(true)
  const [recording, setRecording] = useState(null)
  const [elapsed, setElapsed] = useState(0)
  const [playing, setPlaying] = useState(false)
  const [position, setPosition] = useState(0)
  const [question, setQuestion] = useState('')
  const [chats, setChats] = useState({})
  const [notice, setNotice] = useState('')
  const searchRef = useRef(null)
  const dialogRef = useRef(null)
  const threadRef = useRef(null)
  const meeting = meetings.find(({ id }) => id === selected)
  const dialogue = chats[selected] ?? []
  const activeRecording = Boolean(recording && recording === selected)
  const duration = toSeconds(meeting?.duration ?? '00:00')
  const editedLabel = labels.find((label) => label.id === editing)
  const meetingLabels = labels.filter((label) => meeting?.labels.includes(label.id))
  const live = activeRecording ? liveLines.slice(0, Math.floor(elapsed / 3)).map(([who, line], index) => [formatTime((index + 1) * 3), who, line]) : []

  const filtered = meetings.filter((item) => {
    const names = labels.filter((label) => item.labels.includes(label.id)).map((label) => label.name)
    return [item.title, item.description, ...names, ...item.lines.map((line) => line[2])].join(' ').toLowerCase().includes(query.trim().toLowerCase())
  })

  useEffect(() => {
    if (!recording) return
    const timer = window.setInterval(() => setElapsed((value) => value + 1), 1000)
    return () => window.clearInterval(timer)
  }, [recording])

  useEffect(() => {
    if (!playing) return
    const timer = window.setInterval(() => setPosition((value) => Math.min(value + 1, duration)), 1000)
    return () => window.clearInterval(timer)
  }, [playing, duration])

  useEffect(() => {
    if (position >= duration) setPlaying(false)
  }, [position, duration])

  useEffect(() => {
    if (searching) searchRef.current?.focus()
  }, [searching])

  useEffect(() => {
    if (editing) dialogRef.current?.showModal()
  }, [editing])

  useEffect(() => {
    if (dialogue.length || live.length) threadRef.current?.lastElementChild?.scrollIntoView({ block: 'nearest' })
  }, [dialogue.length, live.length])

  useEffect(() => {
    if (!notice) return
    const timer = window.setTimeout(() => setNotice(''), 2300)
    return () => window.clearTimeout(timer)
  }, [notice])

  function navigate(destination) {
    setPage(destination)
    setSelected(null)
    setMobileDetail(true)
    setPlaying(false)
    setMenu(false)
  }

  function openMeeting(id) {
    setPage('Meeting')
    setSelected(id)
    setTab(tabs[0])
    setMobileDetail(true)
    setPosition(0)
    setPlaying(false)
    setQuestion('')
    setMenu(false)
  }

  function saveMeeting(event) {
    event.preventDefault()
    const title = new FormData(event.currentTarget).get('title').trim()
    if (!title) return
    if (editing === 'rename') {
      setMeetings((current) => current.map((item) => item.id === selected ? { ...item, title } : item))
      dialogRef.current.close()
      return
    }
    const id = crypto.randomUUID()
    setMeetings((current) => [{
      id, title, date: 'Today', time: 'Just now', duration: '00:00', color: 'purple', icon: 'wave',
      labels: [], description: '', lines: [], decisions: [], actions: [],
    }, ...current])
    setQuery('')
    setSearching(false)
    dialogRef.current.close()
    openMeeting(id)
  }

  function saveLabel(event) {
    event.preventDefault()
    const values = new FormData(event.currentTarget)
    const name = values.get('name').trim()
    if (!name) return
    const color = values.get('color')
    setLabels((current) => editedLabel
      ? current.map((label) => label.id === editing ? { ...label, name, color } : label)
      : [...current, { id: crypto.randomUUID(), name, color }])
    dialogRef.current.close()
  }

  function removeLabel() {
    setLabels((current) => current.filter((label) => label.id !== editing))
    setMeetings((current) => current.map((item) => ({ ...item, labels: item.labels.filter((id) => id !== editing) })))
    if (filter === editing) setFilter('')
    dialogRef.current.close()
  }

  function toggleLabel(id, checked) {
    setMeetings((current) => current.map((item) => item.id === selected
      ? { ...item, labels: checked ? [...item.labels, id] : item.labels.filter((labelId) => labelId !== id) }
      : item))
  }

  function toggleRecording() {
    if (recording) {
      const captured = liveLines.slice(0, Math.max(1, Math.floor(elapsed / 3)))
      setMeetings((current) => current.map((item) => {
        if (item.id !== recording) return item
        const offset = toSeconds(item.duration)
        return {
          ...item,
          duration: formatTime(offset + Math.max(1, elapsed)),
          lines: [...item.lines, ...captured.map(([who, line], index) => [formatTime(offset + Math.min(elapsed, (index + 1) * 3)), who, line])],
        }
      }))
      setRecording(null)
      setNotice('Demo recording saved')
      return
    }
    setPlaying(false)
    setElapsed(0)
    setRecording(selected)
    setTab('Transcription')
  }

  function ask(event) {
    event.preventDefault()
    if (!question.trim()) return
    const answer = /action|follow.?up|next|who/i.test(question) ? meeting.actions[0] :
      /decid|decision/i.test(question) ? meeting.decisions[0] : meeting.lines.at(-1)?.[2]
    setChats((current) => ({
      ...current,
      [selected]: [...(current[selected] ?? []), [question.trim(), answer ?? meeting.lines.at(-1)?.[2] ?? 'Start a demo recording to add some context to this meeting.']],
    }))
    setTab('Transcription')
    setQuestion('')
  }

  async function copyTranscript() {
    setMenu(false)
    try {
      await navigator.clipboard.writeText(meeting.lines.map(([time, speaker, line]) => `${time} ${speaker}: ${line}`).join('\n'))
      setNotice('Transcript copied')
    } catch {
      setNotice('Clipboard unavailable')
    }
  }

  function togglePlayback() {
    if (position >= duration) setPosition(0)
    setPlaying((current) => !current)
  }

  return (
    <div className={`app ${mobileDetail ? 'show-detail' : ''}`}>
      <aside className="sidebar" aria-label="Meetings">
        <div className="sidebar-top">
          <div className="wordmark"><Badge icon="wave" color="purple" /> <span>Meeting Record</span></div>
          <div className="sidebar-tools">
            <IconButton icon={Search} label="Search meetings" aria-expanded={searching} onClick={() => {
              setSearching(!searching)
              setQuery('')
            }} />
            <IconButton icon={Plus} label="New meeting" onClick={() => setEditing('create')} />
          </div>
        </div>
        {searching && <input ref={searchRef} className="search" aria-label="Search titles and transcripts" placeholder="Search meetings…" value={query} onChange={(event) => setQuery(event.target.value)} onKeyDown={(event) => {
          if (event.key === 'Escape') { setSearching(false); setQuery('') }
        }} />}
        <nav className="main-nav" aria-label="Workspace">
          {navigation.map(([name, Icon]) => <button key={name} aria-current={page === name ? 'page' : undefined} onClick={() => {
            if (name === 'Home') setFilter('')
            navigate(name)
          }}><Icon />{name}</button>)}
        </nav>
        <nav className="meetings" aria-label="Meeting list">
          <h2>{query ? 'Search results' : 'Recent meetings'}</h2>
          {filtered.map((item) => (
            <button className={`meeting-row ${selected === item.id ? 'current' : ''}`} key={item.id} aria-current={selected === item.id ? 'true' : undefined} onClick={() => openMeeting(item.id)}>
              <Badge icon={item.icon} color={item.color} shape={item.id} />
              <span className="row-text"><strong>{item.title}</strong></span>
              {recording === item.id ? <span className="live-dot" aria-label="Recording" /> : item.labels.length > 0 && <Tag className="row-tag" aria-label="Labeled" />}
            </button>
          ))}
          {!filtered.length && <p className="no-results">No meetings found.</p>}
        </nav>
        <div className="sidebar-bottom"><span className="demo-dot" /> Demo workspace <IconButton icon={CircleHelp} label="About this demo" onClick={() => setNotice('Recordings, playback, and answers are simulated.')} /></div>
      </aside>

      <main className="workspace">
        {page !== 'Meeting' && <>
          <IconButton icon={ArrowLeft} className="back page-back" label="Back to navigation" onClick={() => setMobileDetail(false)} />
          {page === 'Home' && <Home meetings={meetings} labels={labels} filter={filter} setFilter={setFilter} openMeeting={openMeeting} newMeeting={() => setEditing('create')} Badge={Badge} />}
          {page === 'Labels' && <Labels labels={labels} meetings={meetings} editLabel={setEditing} showLabel={(id) => { setFilter(id); navigate('Home') }} />}
          {page === 'Settings' && <Settings settings={settings} setSettings={setSettings} />}
          {recording && <button className="record recording global-record" onClick={toggleRecording}><Square /> Stop {formatTime(elapsed)}</button>}
        </>}
        {meeting && <>
        <header className="workspace-header">
          <IconButton icon={ArrowLeft} className="back" label="Back to meetings" onClick={() => setMobileDetail(false)} />
          <div className="title-pill"><Badge color={meeting.color} icon={meeting.icon} shape={meeting.id} /><h1>{meeting.title}</h1></div>
          <div className="more">
            <IconButton icon={MoreHorizontal} label="Meeting options" aria-expanded={menu} onClick={() => setMenu(!menu)} />
            {menu && <div className="popover">
              <button onClick={() => { setEditing('rename'); setMenu(false) }}>Rename meeting</button>
              <button onClick={() => { setEditing('assign'); setMenu(false) }}><Tag /> Edit labels</button>
              <button onClick={copyTranscript} disabled={!meeting.lines.length}><Copy /> Copy transcript</button>
            </div>}
          </div>
        </header>
        <div className="meeting-meta"><span>{meeting.date}</span><span>{meeting.time}</span>{meetingLabels.map((label) => <Label key={label.id} label={label} />)}</div>
        <div className="tabs" aria-label="Meeting views">
          {tabs.map((name) => <button key={name} className={tab === name ? 'current' : ''} aria-pressed={tab === name} onClick={() => setTab(name)}>{name}</button>)}
        </div>

        <section className="content" ref={threadRef} aria-label={tab}>
          {tab === 'Transcription' && <>
            {meeting.lines.length > 0 && <div className="recording-marker"><AudioLines /> Recording <span>·</span> {duration ? meeting.duration : formatTime(elapsed)} <span>·</span> {settings.model}</div>}
            {[...meeting.lines, ...live].map(([time, who, line], index) => (
              <div key={index} className={`turn ${who === 'Me' ? 'mine' : ''}`}>
                <div className="speaker"><span>{who}</span>{settings.timestamps && <time>{time}</time>}</div>
                <p className="bubble">{line}</p>
              </div>
            ))}
            {!meeting.lines.length && !live.length && <div className="empty">
              <Badge color="purple" icon="wave" /><h2>{activeRecording ? 'Listening…' : 'Your transcript starts here'}</h2>
              <p>{activeRecording ? 'Demo transcript will appear as the recording runs.' : 'Start a demo recording to see the transcript take shape.'}</p>
            </div>}
            {dialogue.map(([prompt, answer], index) => <React.Fragment key={index}>
              <div className="turn mine"><div className="speaker">You</div><p className="bubble">{prompt}</p></div>
              <div className="turn"><div className="speaker"><Sparkles size={13} /> Meeting assistant</div><p className="bubble">{answer}</p></div>
            </React.Fragment>)}
          </>}
          {tab === 'Summary' && <div className="sheet">
            <Badge icon="spark" color={meeting.color} />
            <h2>Meeting summary</h2>
            <p>{meeting.description || 'Your summary will appear here when sample notes are available.'}</p>
            {[['Decisions', meeting.decisions], ['Action items', meeting.actions]].map(([label, items]) => items.length > 0 &&
              <div key={label} className="summary-group"><h3>{label}</h3><ul>{items.map((item) => <li key={item}><Check />{item}</li>)}</ul></div>)}
          </div>}
          {tab === 'Inputs' && <div className="sheet">
            <Badge icon="wave" color={meeting.color} /><h2>Recording inputs</h2>
            {duration ? <><p>Microphone and computer audio are captured as separate tracks.</p>
              {['Microphone', 'Computer audio'].map((track) => <div className="track" key={track}><AudioLines /><strong>{track}{track === 'Microphone' && <small>{settings.microphone}</small>}</strong><span>{meeting.duration}</span></div>)}
            </> : <p>Start a demo recording to add the microphone and computer audio tracks.</p>}
          </div>}
        </section>

        <footer className="dock">
          <div className="transport">
            <IconButton icon={playing ? Pause : Play} label={playing ? 'Pause playback' : 'Play recording'} onClick={togglePlayback} disabled={!duration || !!recording} className="play" />
            <span className="play-time">{formatTime(position)} <span>/ {meeting.duration}</span></span>
            <div className="waveform">
              <div className="wave-bars" aria-hidden="true">{wave.map((height, index) => <i key={index} style={{ '--bar': `${height}%`, '--lit': index / wave.length < position / duration ? 'var(--accent)' : undefined }} />)}</div>
              <input aria-label="Playback position" type="range" min="0" max={duration} value={position} disabled={!duration || !!recording} onChange={(event) => setPosition(Number(event.target.value))} />
            </div>
            <button className={`record ${recording ? 'recording' : ''}`} onClick={toggleRecording}>
              {recording ? <Square /> : <span className="record-dot" />}{recording ? `Stop ${formatTime(elapsed)}` : 'Record'}
            </button>
          </div>
          <form className="composer" onSubmit={ask}>
            <span className="composer-icon"><Sparkles /></span>
            <input aria-label="Ask about this meeting" value={question} onChange={(event) => setQuestion(event.target.value)} placeholder="Ask about this meeting…" />
            <IconButton icon={ArrowUp} label="Send question" className="send" type="submit" disabled={!question.trim()} />
          </form>
        </footer>
        </>}
      </main>

      {editing && <dialog ref={dialogRef} className="new-dialog" aria-labelledby="dialog-title" onClose={() => setEditing(null)}>
        <div className="dialog-header">
          <h2 id="dialog-title">{{ create: 'New meeting', rename: 'Rename meeting', assign: 'Meeting labels', 'new-label': 'New label' }[editing] ?? 'Edit label'}</h2>
          <IconButton icon={X} label="Close" onClick={() => dialogRef.current.close()} />
        </div>
        {editing === 'assign' ? <div className="assign-labels">
          {labels.map((label) => <label key={label.id}><input type="checkbox" checked={meeting.labels.includes(label.id)} onChange={(event) => toggleLabel(label.id, event.target.checked)} /><Label label={label} /></label>)}
          {!labels.length && <p>Create a shared label from the Labels page.</p>}
          <button className="primary" onClick={() => dialogRef.current.close()}>Done</button>
        </div> : editing === 'new-label' || editedLabel ? <form onSubmit={saveLabel}>
          <label htmlFor="label-name">Label name</label>
          <input id="label-name" name="name" defaultValue={editedLabel?.name} required maxLength={28} pattern={String.raw`.*\S.*`} autoFocus />
          <label htmlFor="label-color">Color</label>
          <select id="label-color" name="color" defaultValue={editedLabel?.color ?? 'purple'}>{colors.map((color) => <option key={color} value={color}>{color[0].toUpperCase() + color.slice(1)}</option>)}</select>
          <div className="dialog-actions">
            {editedLabel && <button type="button" className="text-danger" onClick={removeLabel}>Delete label</button>}
            <button className="primary" type="submit">{editedLabel ? 'Save label' : 'Create label'}</button>
          </div>
        </form> : <form onSubmit={saveMeeting}>
          <label htmlFor="meeting-name">Meeting name</label>
          <input id="meeting-name" name="title" placeholder="e.g. Project kickoff" defaultValue={editing === 'rename' ? meeting.title : ''} autoFocus required maxLength={80} pattern={String.raw`.*\S.*`} />
          <button className="primary" type="submit">{editing === 'rename' ? 'Save name' : 'Create meeting'}</button>
        </form>}
      </dialog>}
      {notice && <div className="toast" role="status">{notice}</div>}
    </div>
  )
}

createRoot(document.getElementById('root')).render(<App />)
