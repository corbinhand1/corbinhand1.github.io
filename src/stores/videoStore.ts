import { create } from 'zustand';

interface VideoState {
  isVideoRolling: boolean;
  setVideoRolling: (rolling: boolean) => void;
  triggerVideoSequence: () => void;
  stopVideoSequence: () => void;
  resetVideoState: () => void;
}

export const useVideoStore = create<VideoState>((set) => ({
  isVideoRolling: false,
  setVideoRolling: (rolling: boolean) => {
    console.log('VideoStore: setVideoRolling called with:', rolling);
    set({ isVideoRolling: rolling });
  },
  triggerVideoSequence: () => {
    console.log('VideoStore: triggerVideoSequence called');
    set({ isVideoRolling: true });
  },
  stopVideoSequence: () => {
    console.log('VideoStore: stopVideoSequence called');
    set({ isVideoRolling: false });
  },
  resetVideoState: () => {
    console.log('VideoStore: resetVideoState called');
    set({ isVideoRolling: false });
  },
}));
