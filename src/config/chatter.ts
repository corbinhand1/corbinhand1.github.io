/**
 * Headset chatter + sticky-note copy. Edit freely.
 * `who` must be a short tag; colors live in StageManager's WHO_CLASS.
 */

export const CHATTER: { who: string; text: string }[] = [
  // Audio
  { who: 'AUDIO', text: "Keynote's lav is live in the restroom. Muting. Muted. We all heard it." },
  { who: 'AUDIO', text: 'Whoever is breathing on PRODUCTION, we love you. Please stop.' },
  { who: 'AUDIO', text: 'Walk-in playlist is on shuffle. Shuffle chose the breakup album.' },
  // Lighting
  { who: 'LX', text: 'Haze is up.' },
  { who: 'LX', text: 'The board just asked if I want to install an update. Mid-show. Bold.' },
  // Video
  { who: 'VIDEO', text: "Presenter's laptop is installing updates. 4%. Doors in 10." },
  { who: 'VIDEO', text: 'Slide 47 has a typo. It is in the company name.' },
  // Production / client
  { who: 'PROD', text: 'Client sent the final deck. Filename: FINAL_v12_REAL_final_USE-THIS.key' },
  { who: 'PROD', text: 'CEO would like to "just wing it." The script is 84 pages.' },
  { who: 'PROD', text: 'Client asks if we can move the stage "a little to the left."' },
  { who: 'PROD', text: "New walk-on song from the client. It's the Freebird guitar solo." },
  // Crew
  { who: 'CREW', text: 'Can someone in video put the football game on my multi?' },
  { who: 'CREW', text: "Someone's truck is here. The driver doesn't know what it is and he only speaks Arabic." },
  { who: 'CREW', text: 'Has anyone seen the stagehands?' },
  { who: 'CREW', text: 'Lunch is ready. So is the changeover. Choose wisely.' },
  { who: 'CREW', text: 'Craft services is out of coffee. Please advise. Please hurry.' },
  { who: 'CREW', text: 'Catering is cod again!' },
  // Front of house
  { who: 'FOH', text: 'First question: WiFi password. Second question: also WiFi.' },
  { who: 'FOH', text: 'Guest asking if I can adjust the temperature.' },
  // Green room / talent
  { who: 'ASM', text: 'Talent is asking for green M&Ms.' },
  { who: 'ASM', text: 'The signer is asking for a taller riser.' },
];

export const SM_REPLIES = [
  'Copy.',
  'Copy. Stand by.',
  'Copy. Not my department.',
  '…copy.',
  'Copy. Adding it to the show report.',
  'Copy. We still go on time.',
  'Love that for us.',
];

export const CLEANUP_NOTES = [
  "Who's sweeping up the confetti?",
  'Confetti in the HVAC. Again.',
  'Who ordered 1000 lbs of confetti?',
  'Cleanup budget: $0',
  'Venue says confetti = cleaning fee',
  'Found confetti in the snake box',
  "Confetti in the A1's coffee",
  "Strike starts when we're done",
  'Confetti stuck to the ceiling',
  'Push brooms: 1. Confetti: all of it.',
  'Confetti in the green room',
  'Load-out 2am. Confetti: forever.',
];
