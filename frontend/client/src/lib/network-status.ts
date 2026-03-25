import { useEffect, useState } from "react";

function getOnlineState(): boolean {
  if (typeof window === "undefined") return true;
  return window.navigator.onLine;
}

export function useNetworkStatus() {
  const [isOnline, setIsOnline] = useState<boolean>(getOnlineState);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const onOnline = () => setIsOnline(true);
    const onOffline = () => setIsOnline(false);

    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);

    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, []);

  return { isOnline };
}
