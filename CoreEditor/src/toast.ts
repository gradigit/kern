let activeToast: HTMLElement | null = null;
let fadeTimer: ReturnType<typeof setTimeout> | null = null;

export function showToast(message: string, duration = 2000): void {
  // Remove any existing toast
  if (activeToast) {
    activeToast.remove();
    activeToast = null;
  }
  if (fadeTimer) {
    clearTimeout(fadeTimer);
    fadeTimer = null;
  }

  const toast = document.createElement("div");
  toast.className = "kern-toast";
  toast.textContent = message;
  document.body.appendChild(toast);
  activeToast = toast;

  // Force reflow then fade in
  toast.offsetHeight;
  toast.classList.add("visible");

  fadeTimer = setTimeout(() => {
    toast.classList.remove("visible");
    toast.addEventListener(
      "transitionend",
      () => {
        toast.remove();
        if (activeToast === toast) activeToast = null;
      },
      { once: true },
    );
  }, duration);
}
