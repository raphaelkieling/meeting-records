export const meetings = [
  {
    id: 'design', title: 'Design sync', date: 'Tue, Nov 24', time: '10:30 AM', duration: '24:18', color: 'purple', icon: 'spark', label: 'Design',
    description: 'Reviewing the new onboarding flow and agreeing on what ships in the first pass.',
    lines: [
      ['00:12', 'Me', 'Can we start with the first screen? I want people to know what to do within five seconds of landing there.'],
      ['00:48', 'Other', 'Let’s keep the welcome screen to one action: start a recording. We can introduce labels and summaries once there’s a meeting to work with.'],
      ['02:16', 'Me', 'That feels right. Let’s also make sure the empty state feels intentional, especially when there’s no recording yet.'],
      ['03:04', 'Other', 'I’ll update the empty state and bring a clickable version on Thursday. Then we can try it with two people from outside the team.'],
    ],
    decisions: ['Give the welcome screen one primary action: start a recording.', 'Introduce labels and summaries after the first recording.'],
    actions: ['Update the empty state in the prototype.', 'Bring a clickable version on Thursday and test it with two people.'],
  },
  {
    id: 'planning', title: 'Product planning', date: 'Mon, Nov 23', time: '2:00 PM', duration: '32:04', color: 'pink', icon: 'orbit', label: 'Product',
    description: 'Pilot scope, rollout timing, and success criteria.',
    lines: [['00:06', 'Other', 'Let’s open the pilot to five teams before we announce general availability.'], ['01:22', 'Me', 'Agreed. I’ll pull together the pilot checklist and a short feedback form by Friday.']],
    decisions: ['Run a pilot with five teams before general availability.'],
    actions: ['Prepare a checklist and feedback form by Friday.'],
  },
  {
    id: 'engineering', title: 'Engineering standup', date: 'Mon, Nov 23', time: '9:00 AM', duration: '12:41', color: 'green', icon: 'code', label: 'Engineering',
    description: 'Recording reliability and this week’s handoff.',
    lines: [['00:09', 'Me', 'The recording recovery flow is ready for another round of testing.'], ['01:10', 'Other', 'I’ll cover restarts and confirm both audio tracks are available afterward.']],
    decisions: ['Prioritize tests for interruption and recovery.'],
    actions: ['Verify both audio tracks after a restart.'],
  },
  {
    id: 'research', title: 'Customer interviews', date: 'Fri, Nov 20', time: '3:30 PM', duration: '46:55', color: 'orange', icon: 'mic', label: 'Research',
    description: 'What teams look for when revisiting meeting notes.',
    lines: [['00:24', 'Other', 'I usually open the notes to find a decision or check who volunteered to take something on.'], ['02:08', 'Me', 'Would a short list of decisions and follow-ups cover most of those visits?']],
    decisions: ['Explore a summary organized around decisions and follow-ups.'],
    actions: ['Bring three examples to the next interview.'],
  },
  {
    id: 'weekly', title: 'Weekly team catch-up', date: 'Thu, Nov 19', time: '11:00 AM', duration: '18:26', color: 'blue', icon: 'people', label: 'Team',
    description: 'Shared updates and next week’s priorities.',
    lines: [['00:20', 'Me', 'Let’s keep next week clear for finishing the pilot materials.'], ['01:04', 'Other', 'I can move the backlog review to the following week.']],
    decisions: ['Reserve next week for the pilot materials.'],
    actions: ['Move the backlog review.'],
  },
]

export const formatTime = (seconds) =>
  [Math.floor(seconds / 60), seconds % 60].map((part) => String(part).padStart(2, '0')).join(':')

export const toSeconds = (time) => {
  const [minutes, seconds] = time.split(':').map(Number)
  return minutes * 60 + seconds
}

export const liveLines = [
  ['Me', 'Let’s capture the main decisions as we go.'],
  ['Other', 'I’ll put the follow-up in our shared notes.'],
  ['Me', 'Great. We can review it at the next check-in.'],
]
