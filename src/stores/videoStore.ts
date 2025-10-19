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
    set({ isVideoRolling: rolling });
  },
  triggerVideoSequence: () => {
    set({ isVideoRolling: true });
  },
  stopVideoSequence: () => {
    set({ isVideoRolling: false });
  },
  resetVideoState: () => {
    set({ isVideoRolling: false });
  },
}));
