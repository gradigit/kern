let mermaidModule: typeof import("mermaid") | null = null;
let mermaidInitialized = false;
let lastMermaidTheme = "";
let renderCounter = 0;

function getCurrentTheme(): "dark" | "default" {
  const dataTheme = document.documentElement.getAttribute("data-theme");
  if (dataTheme === "dark") return "dark";
  if (dataTheme === "light") return "default";
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "default";
}

async function ensureMermaid(): Promise<typeof import("mermaid")> {
  const theme = getCurrentTheme();

  if (!mermaidModule) {
    mermaidModule = await import("mermaid");
  }

  // (Re)initialize if first time or theme changed
  if (!mermaidInitialized || theme !== lastMermaidTheme) {
    const isDark = theme === "dark";
    mermaidModule.default.initialize({
      startOnLoad: false,
      // Use "base" theme so themeVariables are fully respected
      theme: "base",
      securityLevel: "loose",
      fontFamily:
        '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
      // htmlLabels: true (default) uses foreignObject + getBoundingClientRect().
      // We do NOT pass a custom container to render() — mermaid's own visible
      // temp element in document.body ensures correct text measurement.
      // (htmlLabels: false has a mermaid v11 bug producing empty <tspan> nodes.)
      themeVariables: isDark
        ? {
            background: "#2c2c2e",
            primaryColor: "#48484a",
            primaryTextColor: "#f5f5f7",
            primaryBorderColor: "#636366",
            lineColor: "#98989d",
            secondaryColor: "#3a3a3c",
            secondaryTextColor: "#f5f5f7",
            secondaryBorderColor: "#636366",
            tertiaryColor: "#2c2c2e",
            tertiaryTextColor: "#f5f5f7",
            tertiaryBorderColor: "#636366",
            noteBkgColor: "#3a3a3c",
            noteTextColor: "#f5f5f7",
            noteBorderColor: "#636366",
            edgeLabelBackground: "#2c2c2e",
            nodeTextColor: "#f5f5f7",
          }
        : {
            primaryColor: "#d6e4ff",
            primaryTextColor: "#1d1d1f",
            primaryBorderColor: "#007aff",
            lineColor: "#6e6e73",
            secondaryColor: "#e3f2ff",
            tertiaryColor: "#f5f5f7",
          },
    });
    mermaidInitialized = true;
    lastMermaidTheme = theme;
  }

  return mermaidModule;
}

/**
 * renderPreview function matching Crepe's CodeBlockConfig.renderPreview signature.
 * Used via featureConfigs[CrepeFeature.CodeMirror].renderPreview to render
 * mermaid diagrams directly inside Crepe's code block preview panel.
 */
export function renderPreview(
  language: string,
  content: string,
  applyPreview: (value: null | string | HTMLElement) => void,
): void | null | string | HTMLElement {
  if (language !== "mermaid") {
    return null;
  }

  const trimmed = content.trim();
  if (!trimmed) {
    return null;
  }

  // Render asynchronously via the callback
  const id = `mermaid-${++renderCounter}`;

  ensureMermaid()
    .then((mod) => {
      // Let mermaid render to its own temp element in document.body.
      // We do NOT pass a custom container because WebKit's getBBox() and
      // getBoundingClientRect() return zeros for off-screen or opacity:0 elements,
      // breaking text label measurement for flowchart/class/state/ER/mindmap.
      // Mermaid's own internal container is on-screen and visible during render,
      // which ensures correct text measurement. The temp element is cleaned up
      // by mermaid automatically after render completes.
      return mod.default.render(id, trimmed);
    })
    .then(({ svg }) => {
      const container = document.createElement("div");
      container.className = "mermaid-container";
      // Parse SVG with the SVG MIME type to preserve foreignObject elements.
      // Using innerHTML on an HTML div strips foreignObject (HTML namespace
      // content inside SVG) because the HTML parser doesn't handle mixed
      // SVG+HTML namespaces correctly.
      const parser = new DOMParser();
      const svgDoc = parser.parseFromString(svg, "image/svg+xml");
      const parseError = svgDoc.querySelector("parsererror");
      if (parseError) {
        // Fallback: if SVG parsing fails, use innerHTML (loses foreignObject)
        container.innerHTML = svg;
      } else {
        container.appendChild(document.importNode(svgDoc.documentElement, true));
      }

      // DOMPurify in Milkdown's preview-panel strips foreignObject children
      // because foreignObject is not in its HTML_INTEGRATION_POINTS (hardcoded,
      // no config option). We bypass it with a marker-and-replace strategy:
      // 1. Pass a simple marker div to applyPreview (survives DOMPurify)
      // 2. Use MutationObserver to detect when the marker appears in the DOM
      // 3. Replace the marker with our correctly-parsed SVG (foreignObject intact)
      const markerId = `mermaid-render-${id}`;
      const marker = document.createElement("div");
      marker.id = markerId;
      marker.className = "mermaid-container";
      applyPreview(marker);

      const observer = new MutationObserver((_mutations, obs) => {
        const el = document.getElementById(markerId);
        if (el) {
          el.replaceWith(container);
          obs.disconnect();
          clearTimeout(safety);
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
      const safety = setTimeout(() => observer.disconnect(), 5000);
    })
    .catch((e) => {
      const errorEl = document.createElement("div");
      errorEl.className = "mermaid-error";
      errorEl.textContent = `Mermaid error: ${e instanceof Error ? e.message : String(e)}`;
      applyPreview(errorEl);
    });

  // Return a loading placeholder synchronously
  return "Rendering diagram…";
}
