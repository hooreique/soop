(() => {
  "use strict";

  const nativeOpen = window.open;

  const navigate = (url) => {
    if (url === undefined || url === null || url === "") {
      return false;
    }

    const destination = String(url);
    if (destination === "about:blank" || destination.startsWith("javascript:")) {
      return false;
    }

    window.location.assign(destination);
    return true;
  };

  window.open = function (url, target, features) {
    if (navigate(url)) {
      return window;
    }
    return nativeOpen.call(window, url, target, features);
  };

  window.addEventListener(
    "click",
    (event) => {
      if (event.defaultPrevented || event.button !== 0) {
        return;
      }

      const anchor = event
        .composedPath()
        .find((node) => node instanceof HTMLAnchorElement);
      const baseTarget = document.querySelector("base[target]")?.target ?? "";
      const target = anchor?.target || baseTarget;

      if (
        !anchor ||
        target.toLowerCase() !== "_blank" ||
        anchor.hasAttribute("download") ||
        !anchor.href
      ) {
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();
      window.location.assign(anchor.href);
    },
    true,
  );
})();
