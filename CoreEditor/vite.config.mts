import { defineConfig, type Plugin } from "vite";
import { readFileSync } from "fs";
import { resolve } from "path";

/**
 * Inlines CSS <link> tags into <style> blocks in the HTML output.
 * This saves one scheme handler round-trip during WKWebView load
 * while keeping JS external for bytecode caching.
 */
function inlineCssPlugin(): Plugin {
  return {
    name: "inline-css",
    enforce: "post",
    generateBundle(_, bundle) {
      for (const [fileName, chunk] of Object.entries(bundle)) {
        if (fileName.endsWith(".html") && chunk.type === "asset") {
          let html = typeof chunk.source === "string"
            ? chunk.source
            : new TextDecoder().decode(chunk.source);

          // Find CSS link tags and inline them
          const linkRegex = /<link\s+rel="stylesheet"\s+crossorigin\s+href="\/([^"]+)">/g;
          let match;
          while ((match = linkRegex.exec(html)) !== null) {
            const cssPath = match[1];
            const cssChunk = bundle[cssPath];
            if (cssChunk && cssChunk.type === "asset") {
              const cssContent = typeof cssChunk.source === "string"
                ? cssChunk.source
                : new TextDecoder().decode(cssChunk.source);
              html = html.replace(match[0], `<style>${cssContent}</style>`);
              // Keep the CSS file in the bundle — Vite's chunk dependency maps
              // reference it by hash, and mermaid's lazy-load will try to fetch it.
              // The styles are already applied via the inline <style> tag above.
            }
          }

          chunk.source = html;
        }
      }
    },
  };
}

export default defineConfig({
  plugins: [inlineCssPlugin()],
  build: {
    target: "safari17",
    outDir: "dist",
    assetsInlineLimit: 0,
    assetsDir: "chunks",
    rollupOptions: {
      output: {
        assetFileNames: "chunks/[name]-[hash][extname]",
        chunkFileNames: "chunks/[name]-[hash].js",
        entryFileNames: "app-[hash].js",
        manualChunks: {
          mermaid: ["mermaid"],
        },
      },
    },
  },
});
