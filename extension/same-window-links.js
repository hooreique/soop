(() => {
  "use strict";

  const navigate = (url) => {
    try {
      if (window.top !== window) {
        window.top.location.href = url;
      } else {
        window.location.assign(url);
      }
    } catch {
      window.location.assign(url);
    }
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
      if (
        event.button !== 0 ||
        event.ctrlKey ||
        event.metaKey ||
        event.shiftKey ||
        event.altKey
      ) {
        return;
      }

      const anchor = event
        .composedPath()
        .find((node) => node instanceof HTMLAnchorElement);
      if (!anchor || anchor.hasAttribute("download") || !anchor.href) {
        return;
      }

      const baseTarget = document.querySelector("base[target]")?.target ?? "";
      const target = (anchor.getAttribute("target") || baseTarget).toLowerCase();
      if (target !== "_blank") {
        return;
      }

      event.preventDefault();
      navigate(anchor.href);
    },
    true,
  );

  window.addEventListener(
    "submit",
    (event) => {
      if (!(event.target instanceof HTMLFormElement)) {
        return;
      }

      const baseTarget = document.querySelector("base[target]")?.target ?? "";
      const target = (event.target.getAttribute("target") || baseTarget).toLowerCase();
      if (target === "_blank") {
        event.target.target = "_self";
      }
    },
    true,
  );
})();
