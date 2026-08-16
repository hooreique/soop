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

  const normalizeLink = (anchor) => {
    anchor.removeAttribute("target");
    anchor.removeAttribute("rel");
  };

  const normalizeLinks = (root) => {
    if (root instanceof HTMLAnchorElement) {
      normalizeLink(root);
    }
    for (const anchor of root.querySelectorAll?.("a") ?? []) {
      normalizeLink(anchor);
    }
  };

  normalizeLinks(document);

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type === "attributes") {
        if (mutation.target instanceof HTMLAnchorElement) {
          normalizeLink(mutation.target);
        }
        continue;
      }

      for (const node of mutation.addedNodes) {
        if (node instanceof Element) {
          normalizeLinks(node);
        }
      }
    }
  });

  observer.observe(document, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["target", "rel"],
  });

  window.addEventListener(
    "click",
    (event) => {
      if (event.button !== 0) {
        return;
      }

      const anchor = event
        .composedPath()
        .find((node) => node instanceof HTMLAnchorElement);
      const baseTarget = document.querySelector("base[target]")?.target ?? "";
      const target = anchor?.target || baseTarget;

      if (
        !anchor ||
        anchor.hasAttribute("download") ||
        !target ||
        target.toLowerCase() === "_self"
      ) {
        return;
      }

      anchor.target = "_self";
      anchor.removeAttribute("rel");
    },
    true,
  );
})();
