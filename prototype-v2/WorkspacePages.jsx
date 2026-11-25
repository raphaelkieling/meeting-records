import React from 'react'
import { AudioLines, ChevronRight, Clock3, FileText, Pencil, Plus, Tag } from 'lucide-react'
import { toSeconds } from './meetings'

export const colors = ['purple', 'pink', 'green', 'orange', 'blue']

export function Label({ label }) {
  return <span className={`label ${label.color}`}>{label.name}</span>
}

export function Home({ meetings, labels, filter, setFilter, openMeeting, newMeeting, Badge }) {
  const total = meetings.reduce((sum, meeting) => sum + toSeconds(meeting.duration), 0)
  const visible = meetings.filter((meeting) => !filter || meeting.labels.includes(filter))
  const currentLabel = labels.find((label) => label.id === filter)

  return <div className="page home">
    <header className="page-heading">
      <div><h1>Home</h1><p>Your meeting library</p></div>
      <button className="primary" onClick={newMeeting}><Plus /> New meeting</button>
    </header>
    <div className="overview">
      <div><Clock3 /><span>Time recorded</span><strong>{Math.floor(total / 3600)}h {Math.floor(total / 60) % 60}m</strong></div>
      <div><FileText /><span>Completed transcriptions</span><strong>{meetings.filter((meeting) => meeting.lines.length).length}</strong></div>
    </div>
    <div className="section-heading">
      <h2>{currentLabel ? currentLabel.name : 'Recent meetings'}</h2>
      <select aria-label="Filter by label" value={filter || ''} onChange={(event) => setFilter(event.target.value)}>
        <option value="">All labels</option>
        {labels.map((label) => <option key={label.id} value={label.id}>{label.name}</option>)}
      </select>
    </div>
    <div className="list-panel">
      {visible.map((meeting) => <button className="library-row" key={meeting.id} onClick={() => openMeeting(meeting.id)}>
        <Badge icon={meeting.icon} color={meeting.color} />
        <span className="library-title"><strong>{meeting.title}</strong><small>{meeting.date} · {meeting.duration}</small></span>
        <span className="library-labels">{labels.filter((label) => meeting.labels.includes(label.id)).map((label) => <Label key={label.id} label={label} />)}</span>
        <ChevronRight className="row-arrow" />
      </button>)}
      {!visible.length && <p className="panel-note">No meetings with this label yet.</p>}
    </div>
  </div>
}

export function Labels({ labels, meetings, editLabel, showLabel }) {
  return <div className="page">
    <header className="page-heading">
      <div><h1>Labels</h1><p>Organize meetings by topic.</p></div>
      <button className="primary" onClick={() => editLabel('new-label')}><Plus /> New label</button>
    </header>
    <div className="list-panel">
      {labels.map((label) => {
        const count = meetings.filter((meeting) => meeting.labels.includes(label.id)).length
        return <div className="label-row" key={label.id}>
          <button className="library-row" onClick={() => showLabel(label.id)}>
            <span className={`label-icon label ${label.color}`}><Tag /></span><strong>{label.name}</strong><small>{count} {count === 1 ? 'meeting' : 'meetings'}</small>
          </button>
          <button className="icon-button" aria-label={`Edit ${label.name}`} title={`Edit ${label.name}`} onClick={() => editLabel(label.id)}><Pencil /></button>
        </div>
      })}
      {!labels.length && <p className="panel-note">Create a label to start organizing your meetings.</p>}
    </div>
  </div>
}

export function Settings({ settings, setSettings }) {
  function update(key, value) {
    setSettings((current) => ({ ...current, [key]: value }))
  }

  return <div className="page">
    <header className="page-heading"><div><h1>Settings</h1><p>Preferences for this demo workspace</p></div></header>
    <h2 className="settings-heading"><AudioLines /> Recording</h2>
    <div className="list-panel">
      <label className="setting-row"><span><strong>Microphone</strong><small>Input shown on demo recordings</small></span>
        <select value={settings.microphone} onChange={(event) => update('microphone', event.target.value)}>
          <option>System default</option><option>Built-in microphone</option><option>USB microphone</option>
        </select>
      </label>
    </div>
    <h2 className="settings-heading"><FileText /> Transcription</h2>
    <div className="list-panel">
      <label className="setting-row"><span><strong>Model</strong><small>Model shown next to the transcript</small></span>
        <select value={settings.model} onChange={(event) => update('model', event.target.value)}>
          <option>Whisper Small</option><option>Whisper Base</option><option>Whisper Large v3</option>
        </select>
      </label>
      <label className="setting-row"><span><strong>Show timestamps</strong><small>Display the start time of each transcript segment</small></span>
        <input type="checkbox" checked={settings.timestamps} onChange={(event) => update('timestamps', event.target.checked)} />
      </label>
    </div>
  </div>
}
