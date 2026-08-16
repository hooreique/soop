(() => {
  "use strict";

  const nativeOpen = window.open;

  window.open = function (url, target, features) {
    const destinationTarget = String(target ?? "_blank").toLowerCase();
    if (
      url === undefined ||
      url === null ||
      url === "" ||
      destinationTarget === "_self" ||
      destinationTarget === "_parent" ||
      destinationTarget === "_top"
    ) {
      return nativeOpen.call(window, url, target, features);
    }

    let destination;
    try {
      destination = new URL(String(url), document.baseURI);
    } catch {
      return nativeOpen.call(window, url, target, features);
    }

    if (destination.protocol !== "http:" && destination.protocol !== "https:") {
      return nativeOpen.call(window, url, target, features);
    }

    try {
      if (window.top !== window) {
        window.top.location.href = destination.href;
      } else {
        window.location.assign(destination.href);
      }
    } catch {
      window.location.assign(destination.href);
    }
    return window.top;
  };
})();
