(() => {
  "use strict";

  const restoreCloseShortcut = (event) => {
    if (
      event.key?.toLowerCase() !== "w" ||
      !event.ctrlKey ||
      event.metaKey ||
      event.altKey ||
      event.shiftKey
    ) {
      return;
    }

    // Preserve Chromium's default Ctrl+W action while hiding it from the page.
    event.stopImmediatePropagation();
    event.stopPropagation();
  };

  window.addEventListener("keydown", restoreCloseShortcut, true);
  document.addEventListener("keydown", restoreCloseShortcut, true);
})();
